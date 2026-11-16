package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local HttpClient = require("crescent.http_client")

-- Fake resty.http object. `response` may set status, headers and chunks.
local function fake(response, options)
    options = options or {}
    local state = { created = 0 }
    local function factory()
        state.created = state.created + 1
        local httpc = {}
        function httpc:set_timeouts(...) state.timeouts = { ... } end
        function httpc:connect(params)
            state.connect = params
            if options.connect_error then return nil, options.connect_error end
            return true
        end
        function httpc:request(params)
            state.request = params
            local chunks, index = response.chunks or {}, 0
            return {
                status = response.status or 200,
                headers = response.headers or {},
                body_reader = function()
                    index = index + 1
                    return chunks[index]
                end,
            }
        end
        function httpc:set_keepalive(timeout, pool)
            state.keepalive = { timeout, pool }
            return true
        end
        function httpc:close() state.closed = true end
        return httpc
    end
    return factory, state
end

local function get_with_base_url_and_params()
    local factory, state = fake({ headers = { ["Content-Type"] = "application/json" }, chunks = { '{"ok":', "true}" } })
    local client = HttpClient.new({ base_url = "https://api.example.com/v1/", timeout = 2, headers = { ["X-Key"] = "k" }, factory = factory })
    local res, err = client:get("/users", { params = { q = "a b", page = 2 } })
    tests.assertNil(err)
    tests.assertEquals(res.status, 200)
    tests.assertEquals(res.body, '{"ok":true}')
    tests.assertTrue(res.data.ok)
    tests.assertEquals(state.connect.scheme, "https")
    tests.assertEquals(state.connect.host, "api.example.com")
    tests.assertEquals(state.connect.port, 443)
    tests.assertEquals(state.connect.ssl_verify, true)
    tests.assertEquals(state.connect.ssl_server_name, "api.example.com")
    tests.assertEquals(state.request.method, "GET")
    tests.assertEquals(state.request.path, "/v1/users?page=2&q=a%20b")
    tests.assertEquals(state.request.headers["X-Key"], "k")
    tests.assertContains(state.request.headers.Accept, "application/json")
    tests.assertEquals(state.timeouts[1], 2000)
    tests.assertEquals(state.keepalive[1], 60000)
    tests.assertNil(state.closed)
end

local function post_encodes_json()
    local factory, state = fake({ status = 201, chunks = { "created" } })
    local client = HttpClient.new({ factory = factory, ssl_verify = false })
    local res = client:post("http://localhost:8081/items?x=1", { name = "Ada" })
    tests.assertEquals(res.status, 201)
    tests.assertEquals(res.data, "created")
    tests.assertEquals(state.request.body, '{"name":"Ada"}')
    tests.assertEquals(state.request.headers["Content-Type"], "application/json")
    tests.assertEquals(state.request.path, "/items?x=1")
    tests.assertEquals(state.connect.port, 8081)
    tests.assertEquals(state.connect.ssl_verify, false)

    client:put("http://localhost/items/1", "raw", { headers = { ["content-type"] = "text/plain" } })
    tests.assertEquals(state.request.method, "PUT")
    tests.assertEquals(state.request.body, "raw")
    tests.assertEquals(state.request.headers["content-type"], "text/plain")
    tests.assertNil(state.request.headers["Content-Type"])
    client:patch("http://localhost/items/1", { a = 1 })
    tests.assertEquals(state.request.method, "PATCH")
    client:delete("http://localhost/items/1")
    tests.assertEquals(state.request.method, "DELETE")
    client:head("http://localhost/")
    tests.assertEquals(state.request.method, "HEAD")
    client:options("http://localhost/")
    tests.assertEquals(state.request.method, "OPTIONS")
end

local function error_status_returns_error()
    local factory = fake({ status = 404, headers = { ["content-type"] = "application/json" }, chunks = { '{"error":"nope"}' } })
    local res, err = HttpClient.new({ factory = factory }):get("http://example.com/missing")
    tests.assertNil(res)
    tests.assertEquals(err.status, 404)
    tests.assertEquals(err.data.error, "nope")
    tests.assertEquals(tostring(err), "request failed with status 404")
end

local function enforces_max_response_size()
    local factory, state = fake({ chunks = { "12345", "67890", "abc" } })
    local res, err = HttpClient.new({ factory = factory, max_response_size = 8 }):get("http://example.com/")
    tests.assertNil(res)
    tests.assertEquals(err.message, "response too large")
    tests.assertTrue(state.closed)
    tests.assertNil(state.keepalive)

    local declared, declared_state = fake({ headers = { ["Content-Length"] = "100" }, chunks = { "x" } })
    res, err = HttpClient.new({ factory = declared, max_response_size = 10 }):get("http://example.com/")
    tests.assertNil(res)
    tests.assertEquals(err.message, "response too large")
    tests.assertTrue(declared_state.closed)
end

local function rejects_invalid_input()
    local factory, state = fake({})
    local client = HttpClient.new({ factory = factory })
    local res, err = client:get("http://example.com/", { headers = { ["X-Evil"] = "a\r\nInjected: 1" } })
    tests.assertNil(res)
    tests.assertContains(err.message, "invalid value for header")
    res, err = client:get("http://example.com/", { headers = { ["Bad Name"] = "x" } })
    tests.assertNil(res)
    res, err = client:get("ftp://example.com/")
    tests.assertContains(err.message, "unsupported URL scheme")
    res, err = client:get("http://user:pass@example.com/")
    tests.assertContains(err.message, "credentials")
    res, err = client:request({ url = "http://example.com/", method = "TRACE" })
    tests.assertContains(err.message, "invalid HTTP method")
    res, err = client:get("/relative-without-base")
    tests.assertNotNil(err)
    tests.assertEquals(state.created, 0, "no connection may be attempted for invalid input")
end

local function connection_failure()
    local factory = fake({}, { connect_error = "connection refused" })
    local res, err = HttpClient.new({ factory = factory }):get("http://127.0.0.1:1/")
    tests.assertNil(res)
    tests.assertContains(err.message, "connection refused")
end

local function parse_url()
    local target = HttpClient.parse_url("https://[::1]:8443/a/b?c=d#frag")
    tests.assertEquals(target.host, "::1")
    tests.assertEquals(target.port, 8443)
    tests.assertEquals(target.path, "/a/b")
    tests.assertEquals(target.query, "c=d")
    target = HttpClient.parse_url("http://example.com?x=1")
    tests.assertEquals(target.path, "/")
    tests.assertEquals(target.query, "x=1")
    tests.assertNil(HttpClient.parse_url("http://example.com:99999/"))
    tests.assertNil(HttpClient.parse_url("http://exa mple.com/"))
    tests.assertNil(HttpClient.parse_url("example.com"))
end

local function default_factory_uses_resty_http()
    local ok, http = pcall(require, "resty.http")
    tests.assertTrue(ok, "lua-resty-http must be installed in lua_modules")
    tests.assertIsFunction(http.new)
    tests.assertIsFunction(HttpClient.get)
    tests.assertIsFunction(HttpClient.create)
end

assert(tests.runSuite("HTTP client", {
    get_with_base_url_and_params = get_with_base_url_and_params,
    post_encodes_json = post_encodes_json,
    error_status_returns_error = error_status_returns_error,
    enforces_max_response_size = enforces_max_response_size,
    rejects_invalid_input = rejects_invalid_input,
    connection_failure = connection_failure,
    parse_url = parse_url,
    default_factory_uses_resty_http = default_factory_uses_resty_http,
}))
