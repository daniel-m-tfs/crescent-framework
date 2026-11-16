package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")

local function silent_app(config)
    config = config or {}
    config.debug = config.debug or false
    config.logged = {}
    config.logger = function(level, message) config.logged[#config.logged + 1] = { level, message } end
    return Crescent.new(config), config.logged
end

local function fake_ngx(options)
    local output = {}
    local api = {
        req = {
            get_headers = function() return options.headers or {} end,
            get_method = function() return options.method or "GET" end,
            get_uri_args = function() return {} end,
            read_body = function() end,
            get_body_data = function() return options.body_data end,
            get_body_file = function() return options.body_file end,
        },
        var = { uri = options.uri or "/", request_id = options.request_id },
        header = {},
        print = function(value) output[#output + 1] = value end,
    }
    return api, output
end

local function handle(app, request)
    request.headers = request.headers or {}
    request.query = request.query or {}
    local writer = { headers = {}, sent = false }
    app:handle(request, writer)
    return writer
end

local function body_spooled_to_file()
    local path = os.tmpname()
    local file = assert(io.open(path, "wb"))
    file:write('{"items":[1,2,3]}')
    file:close()

    local app = silent_app()
    app:post("/big", function(ctx) return ctx:json(200, { count = #ctx.body.items }) end)
    local api, output = fake_ngx({
        method = "POST", uri = "/big", body_file = path,
        headers = { ["Content-Type"] = "application/json" },
    })
    app:run(api)
    os.remove(path)
    tests.assertEquals(api.status, 200)
    tests.assertContains(output[1], '"count":3')
end

local function body_output_has_no_trailing_newline()
    local app = silent_app()
    app:get("/", function(ctx) return ctx:text(200, "exact") end)
    local api, output = fake_ngx({})
    app:run(api)
    tests.assertEquals(table.concat(output), "exact")
end

local function malformed_json_code()
    local app = silent_app()
    app:post("/json", function() error("must not run") end)
    local writer = handle(app, {
        method = "POST", path = "/json", body_error = "bad", body_error_code = "malformed_json",
    })
    tests.assertEquals(writer.status, 400)
    tests.assertContains(writer.body, '"code":"malformed_json"')

    local api = fake_ngx({
        method = "POST", uri = "/json", body_data = "{bad",
        headers = { ["Content-Type"] = "application/json" },
    })
    app:run(api)
    tests.assertEquals(api.status, 400)
    tests.assertEquals(api.header["Content-Type"], "application/json; charset=utf-8")
end

local function request_id_precedence()
    local app = silent_app()
    app:get("/", function(ctx) return ctx:text(200, ctx.request_id) end)
    local upstream = handle(app, { method = "GET", path = "/", upstream_request_id = "from-proxy", request_id = "abc" })
    tests.assertEquals(upstream.body, "from-proxy")
    local nginx = handle(app, { method = "GET", path = "/", upstream_request_id = "bad id!", request_id = "abc" })
    tests.assertEquals(nginx.body, "abc")
end

local function head_falls_back_to_get()
    local app = silent_app()
    app:get("/page", function(ctx) return ctx:text(200, "body") end)
    local writer = handle(app, { method = "HEAD", path = "/page" })
    tests.assertEquals(writer.status, 200)
end

local function returned_values_become_responses()
    local app, logged = silent_app()
    app:get("/table", function() return { ok = true } end)
    app:get("/string", function() return "plain" end)
    app:get("/nothing", function() end)

    local table_writer = handle(app, { method = "GET", path = "/table" })
    tests.assertEquals(table_writer.status, 200)
    tests.assertContains(table_writer.body, '"ok":true')

    local string_writer = handle(app, { method = "GET", path = "/string" })
    tests.assertEquals(string_writer.body, "plain")

    local nothing_writer = handle(app, { method = "GET", path = "/nothing" })
    tests.assertEquals(nothing_writer.status, 500)
    tests.assertContains(nothing_writer.body, '"code":"empty_response"')
    tests.assertEquals(#logged, 1)
end

local function errors_are_logged_but_hidden()
    local app, logged = silent_app()
    app:get("/boom", function() error("db password is hunter2") end)
    local writer = handle(app, { method = "GET", path = "/boom", request_id = "rid-1" })
    tests.assertEquals(writer.status, 500)
    tests.assertNotContains(writer.body, "hunter2")
    tests.assertEquals(#logged, 1)
    tests.assertEquals(logged[1][1], "error")
    tests.assertContains(logged[1][2], "rid-1")
    tests.assertContains(logged[1][2], "hunter2")
end

local function json_arrays_round_trip()
    local json = require("crescent.json")
    local decoded = json.decode('{"tags":[]}')
    tests.assertEquals(json.encode(decoded), '{"tags":[]}')
    tests.assertEquals(json.encode({ list = json.empty_array }), '{"list":[]}')
    tests.assertEquals(json.encode({ path = "/a/b" }), '{"path":"/a/b"}')
end

local function response_helpers()
    local app = silent_app()
    app:get("/local", function(ctx) return ctx:redirect("/home") end)
    app:get("/external", function(ctx) return ctx:redirect("https://evil.example/") end)
    app:get("/protocol-relative", function(ctx) return ctx:redirect("//evil.example/") end)
    app:get("/allowed", function(ctx)
        return ctx:redirect("https://good.example/x", 301, { allowed_hosts = { "good.example" } })
    end)
    app:get("/crlf", function(ctx) return ctx:redirect("/home\r\nSet-Cookie: x=1") end)
    app:delete("/item", function(ctx) return ctx:no_content() end)
    app:get("/bearer", function(ctx) return ctx:text(200, ctx:get_bearer() or "none") end)

    local local_writer = handle(app, { method = "GET", path = "/local" })
    tests.assertEquals(local_writer.status, 302)
    tests.assertEquals(local_writer.headers.Location, "/home")
    tests.assertEquals(handle(app, { method = "GET", path = "/external" }).status, 400)
    tests.assertEquals(handle(app, { method = "GET", path = "/protocol-relative" }).status, 400)
    local allowed = handle(app, { method = "GET", path = "/allowed" })
    tests.assertEquals(allowed.status, 301)
    tests.assertEquals(allowed.headers.Location, "https://good.example/x")
    tests.assertEquals(handle(app, { method = "GET", path = "/crlf" }).status, 400)
    tests.assertEquals(handle(app, { method = "DELETE", path = "/item" }).status, 204)
    local bearer = handle(app, { method = "GET", path = "/bearer", headers = { authorization = "Bearer abc.def" } })
    tests.assertEquals(bearer.body, "abc.def")
end

local function header_injection_is_rejected()
    local app = silent_app()
    app:get("/inject", function(ctx)
        ctx:header("X-Test", "a\r\nSet-Cookie: x=1")
        return ctx:text(200, "unreachable")
    end)
    local writer = handle(app, { method = "GET", path = "/inject" })
    tests.assertEquals(writer.status, 500)
    tests.assertNil(writer.headers["X-Test"])
end

local function client_errors_become_4xx()
    local Model = require("crescent.model")
    local User = Model:extend({ table = "users" })
    local fake_db = {
        query = function() return {} end,
        execute = function() return { affected_rows = 0 } end,
        transaction = function() end, connect = function() end, close = function() end,
    }
    local app, logged = silent_app({ db = fake_db })
    app:get("/users/{id}", function(ctx)
        return ctx:json(200, User:find_or_fail(tonumber(ctx.params.id), ctx.db):to_table())
    end)
    local writer = handle(app, { method = "GET", path = "/users/9" })
    tests.assertEquals(writer.status, 404)
    tests.assertContains(writer.body, '"code":"model_not_found"')
    tests.assertNotContains(writer.body, "users not found")
    tests.assertEquals(#logged, 0, "client errors are not logged as failures")
end

local function views_with_layout()
    local app = silent_app({ root = ".", views_root = "tests/fixtures/views" })
    app:get("/page", function(ctx)
        return ctx:view("hello.etlua", { name = "Ada", trusted = "" }, { layout = "layout.etlua", status = 201 })
    end)
    app:get("/plain", function(ctx) return ctx:view("hello.etlua", { name = "Bob", trusted = "" }, 202) end)
    local page = handle(app, { method = "GET", path = "/page" })
    tests.assertEquals(page.status, 201)
    tests.assertContains(page.body, "<main>Hello Ada")
    tests.assertContains(page.body, "</main></body></html>")
    local plain = handle(app, { method = "GET", path = "/plain" })
    tests.assertEquals(plain.status, 202)
    tests.assertNotContains(plain.body, "<main>")

    local defaulted = silent_app({ root = ".", views_root = "tests/fixtures/views", view_layout = "layout.etlua" })
    defaulted:get("/", function(ctx) return ctx:view("hello.etlua", { name = "Cy", trusted = "" }) end)
    defaulted:get("/bare", function(ctx)
        return ctx:view("hello.etlua", { name = "Di", trusted = "" }, { layout = false })
    end)
    tests.assertContains(handle(defaulted, { method = "GET", path = "/" }).body, "<main>Hello Cy")
    tests.assertNotContains(handle(defaulted, { method = "GET", path = "/bare" }).body, "<main>")
end

local function env_precedence()
    local Env = require("crescent.env")
    local parsed = Env.parse('A=1\nexport B="two words"\n# comment\nC=3 # inline\nD=\'x # y\'\n')
    tests.assertEquals(parsed.A, "1")
    tests.assertEquals(parsed.B, "two words")
    tests.assertEquals(parsed.C, "3")
    tests.assertEquals(parsed.D, "x # y")
    tests.assertEquals(Env.get("HOME"), os.getenv("HOME"), "process environment must win")
    tests.assertEquals(Env.get("CRESCENT_UNSET_VARIABLE", "fallback"), "fallback")
end

assert(tests.runSuite("Runtime", {
    body_spooled_to_file = body_spooled_to_file,
    body_output_has_no_trailing_newline = body_output_has_no_trailing_newline,
    malformed_json_code = malformed_json_code,
    request_id_precedence = request_id_precedence,
    head_falls_back_to_get = head_falls_back_to_get,
    returned_values_become_responses = returned_values_become_responses,
    errors_are_logged_but_hidden = errors_are_logged_but_hidden,
    json_arrays_round_trip = json_arrays_round_trip,
    response_helpers = response_helpers,
    header_injection_is_rejected = header_injection_is_rejected,
    env_precedence = env_precedence,
    client_errors_become_4xx = client_errors_become_4xx,
    views_with_layout = views_with_layout,
}))
