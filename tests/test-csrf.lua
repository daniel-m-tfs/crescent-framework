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
    -- Test-only: exposes the raw session secret and simulates a login.
    app:get("/secret", function(ctx)
        ctx:csrf_token()
        return ctx:text(200, ctx.session:get(csrf.SESSION_KEY))
    end)
    app:post("/login", function(ctx)
        ctx.session:regenerate()
        return ctx:text(200, ctx:csrf_token())
    end)
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
        tests.assertEquals(#token, 86, "masked 256-bit token")
        tests.assertMatches(token, "^[A-Za-z0-9_%-]+$")
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = token }).body, "accepted")
        tests.assertEquals(request("POST", "/submit", { ["x-csrf-token"] = token }).body, "accepted")
        tests.assertEquals(request("DELETE", "/item", { ["x-csrf-token"] = token }).body, "deleted")
    end,

    -- BREACH: every response carries a differently masked token, the session
    -- secret itself never appears in a response, and old masks stay valid.
    masked_per_request = function()
        local request = browser(new_app())
        local first = request("GET", "/form").body
        local second = request("GET", "/form").body
        tests.assertNotEquals(first, second, "a fresh mask per request")
        local secret = request("GET", "/secret").body
        tests.assertEquals(#secret, 43)
        local raw_secret = csrf.unmask(first)
        tests.assertEquals(raw_secret, csrf.unmask(second), "both masks carry the same secret")
        for _, token in ipairs({ first, second }) do
            tests.assertNotContains(token, secret)
            tests.assertEquals(request("POST", "/submit", {}, { _csrf = token }).status, 200)
        end
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = secret }).status, 403,
            "the unmasked secret is not a token")
    end,

    rejects_tampered_tokens = function()
        local request = browser(new_app())
        local token = request("GET", "/form").body
        local flipped = token:sub(1, 50) .. (token:sub(51, 51) == "A" and "B" or "A") .. token:sub(52)
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = flipped }).status, 403)
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = token:sub(1, 85) }).status, 403)
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = string.rep("A", 86) }).status, 403)
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = string.rep("x", 100000) }).status, 403)
        tests.assertNil(csrf.unmask("not base64 !!"))
    end,

    login_rotates_the_secret = function()
        local request = browser(new_app())
        local before = request("GET", "/form").body
        local after = request("POST", "/login", {}, { _csrf = before })
        tests.assertEquals(after.status, 200)
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = before }).status, 403,
            "tokens issued before login stop working")
        tests.assertEquals(request("POST", "/submit", {}, { _csrf = after.body }).status, 200)
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
