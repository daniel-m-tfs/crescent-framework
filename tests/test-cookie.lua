package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local Cookie = require("crescent.cookie")

local SECRET = "cookie-test-secret-0123456789abcdef"
local OLD_SECRET = "previous-cookie-secret-0123456789ab"

local function new_app(config)
    config = config or {}
    config.logger = function() end
    if config.secret_key == nil then config.secret_key = SECRET end
    return Crescent.new(config)
end

local function request(app, method, path, headers)
    local writer = { headers = {}, sent = false }
    app:handle({ method = method, path = path, headers = headers or {}, query = {} }, writer)
    return writer
end

local function set_cookies(writer)
    local value = writer.headers["Set-Cookie"]
    if type(value) == "string" then return { value } end
    return value or {}
end

local suite = {
    parse_basic_and_tolerant = function()
        local parsed = Cookie.parse('a=1; b = two ; c="quoted"; =novalue; broken; d=x=y; a=second; e=%E2%9C%93; f=%zz')
        tests.assertEquals(parsed.a, "1", "first occurrence wins")
        tests.assertEquals(parsed.b, "two")
        tests.assertEquals(parsed.c, "quoted")
        tests.assertEquals(parsed.d, "x=y")
        tests.assertEquals(parsed.e, "\226\156\147", "percent-decoded")
        tests.assertEquals(parsed.f, "%zz", "invalid escapes are kept")
        tests.assertNil(parsed.broken)
        tests.assertNil(parsed[""])
        tests.assertTableEquals(Cookie.parse(nil), {})
        tests.assertTableEquals(Cookie.parse(""), {})
        tests.assertEquals(Cookie.parse({ "x=1", "y=2" }).y, "2", "multiple Cookie headers are joined")
    end,

    serialize_defaults_and_attributes = function()
        tests.assertEquals(Cookie.serialize("id", "abc"), "id=abc; Path=/; HttpOnly; SameSite=Lax")
        local full = Cookie.serialize("id", "a b;c%", {
            path = "/app", domain = "example.com", max_age = 60.9, expires = 0,
            http_only = false, secure = true, same_site = "strict",
        })
        tests.assertEquals(full, "id=a%20b%3Bc%25; Path=/app; Domain=example.com; Max-Age=60; "
            .. "Expires=Thu, 01-Jan-70 00:00:00 GMT; Secure; SameSite=Strict")
        tests.assertEquals(Cookie.parse(full:match("^([^;]+)")).id, "a b;c%", "values round-trip")
        tests.assertContains(Cookie.serialize("x", "1", { same_site = "None", secure = true }), "SameSite=None")
    end,

    serialize_rejects_invalid_input = function()
        tests.assertError(function() Cookie.serialize("bad name", "x") end, "invalid cookie name")
        tests.assertError(function() Cookie.serialize("a;b", "x") end, "invalid cookie name")
        tests.assertError(function() Cookie.serialize("ok", {}) end, "must be a string")
        tests.assertError(function() Cookie.serialize("ok", "x", { path = "/a\r\nX: y" }) end, "invalid cookie path")
        tests.assertError(function() Cookie.serialize("ok", "x", { domain = "a.com; Secure" }) end, "invalid cookie domain")
        tests.assertError(function() Cookie.serialize("ok", "x", { expires = "x\ny" }) end, "invalid cookie expires")
        tests.assertError(function() Cookie.serialize("ok", "x", { same_site = "Weird" }) end, "same_site")
        tests.assertError(function() Cookie.serialize("ok", "x", { same_site = "None" }) end, "requires secure")
        tests.assertError(function() Cookie.serialize("ok", "x", { max_age = "1" }) end, "max_age")
        -- CR/LF in values is encoded, never emitted raw.
        tests.assertEquals(Cookie.serialize("ok", "a\r\nb", { path = false, http_only = false, same_site = false }),
            "ok=a%0D%0Ab")
    end,

    ctx_reads_and_caches_cookies = function()
        local app = new_app()
        local parses = 0
        local original = Cookie.parse
        app:get("/", function(ctx)
            Cookie.parse = function(...) parses = parses + 1 return original(...) end
            local a, b = ctx:cookie("a"), ctx:cookie("b")
            Cookie.parse = original
            return ctx:text(200, tostring(a) .. "," .. tostring(b))
        end)
        local writer = request(app, "GET", "/", { cookie = "a=1; b=%20x" })
        tests.assertEquals(writer.body, "1, x")
        tests.assertEquals(parses, 1, "the Cookie header is parsed once per request")
    end,

    ctx_set_and_clear_cookie = function()
        local app = new_app()
        app:get("/set", function(ctx)
            ctx:set_cookie("theme", "dark")
            ctx:set_cookie("lang", "pt", { max_age = 3600, same_site = "Strict" })
            ctx:set_cookie("theme", "light")
            return ctx:text(200, "ok")
        end)
        app:get("/clear", function(ctx)
            ctx:clear_cookie("theme", { path = "/" })
            return ctx:text(200, "ok")
        end)
        local cookies = set_cookies(request(app, "GET", "/set"))
        tests.assertEquals(#cookies, 2, "setting a cookie twice keeps only the last value")
        tests.assertEquals(cookies[1], "lang=pt; Path=/; Max-Age=3600; HttpOnly; Secure; SameSite=Strict")
        tests.assertEquals(cookies[2], "theme=light; Path=/; HttpOnly; Secure; SameSite=Lax")

        local cleared = set_cookies(request(app, "GET", "/clear"))[1]
        tests.assertContains(cleared, "theme=; Path=/; Max-Age=0; Expires=Thu, 01-Jan-70 00:00:00 GMT")
    end,

    secure_default_follows_debug = function()
        local app = new_app({ debug = true })
        app:get("/", function(ctx)
            ctx:set_cookie("a", "1")
            ctx:set_cookie("b", "1", { secure = true })
            return ctx:text(200, "ok")
        end)
        local cookies = set_cookies(request(app, "GET", "/"))
        tests.assertNotContains(cookies[1], "Secure")
        tests.assertContains(cookies[2], "Secure")
    end,

    signed_cookies_detect_tampering = function()
        local app = new_app()
        app:get("/set", function(ctx)
            ctx:set_cookie("uid", "42", { signed = true })
            return ctx:text(200, "ok")
        end)
        app:get("/read", function(ctx) return ctx:text(200, tostring(ctx:signed_cookie("uid"))) end)
        local header = set_cookies(request(app, "GET", "/set"))[1]
        local value = header:match("^uid=([^;]+)")
        tests.assertMatches(value, "^42%.[%w_%-]+$")

        tests.assertEquals(request(app, "GET", "/read", { cookie = "uid=" .. value }).body, "42")
        local tampered = value:gsub("^42", "43")
        tests.assertEquals(request(app, "GET", "/read", { cookie = "uid=" .. tampered }).body, "nil")
        tests.assertEquals(request(app, "GET", "/read", { cookie = "uid=42" }).body, "nil")
        tests.assertEquals(request(app, "GET", "/read", { cookie = "other=" .. value }).body, "nil")

        -- A signature is bound to the cookie name.
        tests.assertNil(Cookie.unsign("other", value, { SECRET }))
    end,

    signed_cookie_key_rotation = function()
        local signed = Cookie.sign("uid", "7", OLD_SECRET)
        local rotated = new_app({ secret_key_fallbacks = { OLD_SECRET } })
        rotated:get("/", function(ctx) return ctx:text(200, tostring(ctx:signed_cookie("uid"))) end)
        tests.assertEquals(request(rotated, "GET", "/", { cookie = "uid=" .. signed }).body, "7")

        local without = new_app()
        without:get("/", function(ctx) return ctx:text(200, tostring(ctx:signed_cookie("uid"))) end)
        tests.assertEquals(request(without, "GET", "/", { cookie = "uid=" .. signed }).body, "nil")

        -- New cookies are always signed with the current key.
        tests.assertNotNil(Cookie.unsign("uid", Cookie.sign("uid", "7", SECRET), { SECRET }))
    end,

    secrets_validation = function()
        tests.assertError(function() Cookie.secrets({ secret_key = "short" }) end, "at least 32")
        tests.assertError(function() Cookie.secrets({ secret_key = SECRET, secret_key_fallbacks = { "x" } }) end,
            "secret_key_fallbacks")
        local list = Cookie.secrets({ secret_key = SECRET, secret_key_fallbacks = OLD_SECRET })
        tests.assertEquals(#list, 2)
        tests.assertEquals(list[1], SECRET)
    end,
}

assert(tests.runSuite("Cookies", suite))
