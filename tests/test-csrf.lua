package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local session = require("crescent.middleware.session")
local csrf = require("crescent.middleware.csrf")

local SECRET = "csrf-test-secret-0123456789abcdefgh"

local function new_app(options)
    local logged = {}
    local app = Crescent.new({
        secret_key = SECRET,
        view_renderer = require("crescent.view").new("tests/fixtures/views"),
        logger = function(_, message) logged[#logged + 1] = message end,
    })
    app:use(session.create())
    app:use(csrf.create(options))
    app:get("/form", function(ctx) return ctx:text(200, ctx:csrf_token()) end)
    app:get("/view", function(ctx) return ctx:view("form.etlua") end)
    app:post("/submit", function(ctx) return ctx:text(200, "accepted") end)
    app:delete("/item", function(ctx) return ctx:text(200, "deleted") end)
    return app, logged
end

local function browser(app)
    local jar = {}
    return function(method, path, headers, body)
        headers = headers or {}
        local parts = {}
        for name, value in pairs(jar) do parts[#parts + 1] = name .. "=" .. value end
        headers.cookie = table.concat(parts, "; ")
        local writer = { headers = {}, sent = false }
        app:handle({ method = method, path = path, headers = headers, query = {}, body = body }, writer)
        local set = writer.headers["Set-Cookie"]
        if type(set) == "string" then set = { set } end
        for _, header in ipairs(set or {}) do
            local name, value = header:match("^([^=]+)=([^;]*)")
            jar[name] = value
        end
        return writer
    end
end

local suite = {
    accepts_token_from_field_or_header = function()
        local request = browser(new_app())
        local token = request("GET", "/form").body
        tests.assertTrue(#token >= 43, "256-bit token")
        tests.assertEquals(request("GET", "/form").body, token, "the token is stable within the session")
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = token }).body, "accepted")
        tests.assertEquals(request("POST", "/submit", { ["x-csrf-token"] = token }).body, "accepted")
        tests.assertEquals(request("DELETE", "/item", { ["x-csrf-token"] = token }).body, "deleted")
    end,

    rejects_missing_or_wrong_token = function()
        local request = browser(new_app())
        local token = request("GET", "/form").body
        local missing = request("POST", "/submit")
        tests.assertEquals(missing.status, 403)
        tests.assertContains(missing.body, '"code":"csrf_invalid"')
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = token .. "x" }).status, 403)
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = { token } }).status, 403)
        tests.assertEquals(request("DELETE", "/item", { ["x-csrf-token"] = "nope" }).status, 403)

        -- Without a session token (fresh browser), even an "empty" match fails.
        local fresh = browser(new_app())
        tests.assertEquals(fresh("POST", "/submit", {}, { _csrf = "" }).status, 403)
        -- A token from another session is useless.
        tests.assertEquals(fresh("POST", "/submit", {}, { _csrf = token }).status, 403)
    end,

    safe_methods_and_skip = function()
        local request = browser(new_app({
            skip = function(ctx) return ctx:get_bearer() ~= nil end,
            safe_methods = { "GET", "HEAD", "OPTIONS", "DELETE" },
        }))
        tests.assertEquals(request("DELETE", "/item").status, 200, "configured as safe")
        tests.assertEquals(request("POST", "/submit", { authorization = "Bearer abc" }).status, 200)
        tests.assertEquals(request("POST", "/submit").status, 403)
    end,

    custom_field_and_header = function()
        local request = browser(new_app({ field = "authenticity_token", header = "X-XSRF-Token" }))
        local token = request("GET", "/form").body
        tests.assertEquals(request("POST", "/submit", {}, { authenticity_token = token }).status, 200)
        tests.assertEquals(request("POST", "/submit", { ["x-xsrf-token"] = token }).status, 200)
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = token }).status, 403)
    end,

    view_helpers = function()
        local request = browser(new_app())
        local page = request("GET", "/view")
        tests.assertEquals(page.status, 200, tostring(page.body))
        local token = page.body:match('name="_csrf" value="([^"]+)"')
        tests.assertNotNil(token, page.body)
        tests.assertContains(page.body, 'name="token-copy" value="' .. token .. '"')
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = token }).status, 200)
    end,

    requires_session_middleware = function()
        local logged = {}
        local app = Crescent.new({ logger = function(_, message) logged[#logged + 1] = message end })
        app:use(csrf.create())
        app:post("/submit", function(ctx) return ctx:text(200, "x") end)
        local writer = { headers = {}, sent = false }
        app:handle({ method = "POST", path = "/submit", headers = {}, query = {} }, writer)
        tests.assertEquals(writer.status, 500)
        tests.assertContains(logged[1], "requires the session middleware")
    end,
}

assert(tests.runSuite("CSRF", suite))
