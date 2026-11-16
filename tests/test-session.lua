package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local Session = require("crescent.session")
local Crypto = require("crescent.security.crypto")
local Base64 = require("crescent.security.base64")

local SECRET = "session-test-secret-0123456789abcdef"
local OLD_SECRET = "old-session-secret-0123456789abcdefg"

local clock = 1000000
Crypto.now = function() return clock end

local function new_app(options, config)
    config = config or {}
    if config.secret_key == nil then config.secret_key = SECRET end
    local logged = {}
    config.logger = function(level, message) logged[#logged + 1] = message end
    local app = Crescent.new(config)
    app:use(Session.middleware(options))
    app:get("/get/{key}", function(ctx) return ctx:text(200, tostring(ctx.session:get(ctx.params.key))) end)
    app:get("/set/{key}/{value}", function(ctx)
        ctx.session:set(ctx.params.key, ctx.params.value)
        return ctx:text(200, "ok")
    end)
    app:get("/noop", function(ctx) return ctx:text(200, "noop") end)
    return app, logged
end

-- A tiny browser: keeps cookies between requests.
local function browser(app)
    local jar = {}
    local agent = {}
    function agent.request(method, path)
        local parts = {}
        for name, value in pairs(jar) do parts[#parts + 1] = name .. "=" .. value end
        local writer = { headers = {}, sent = false }
        app:handle({ method = method, path = path, headers = { cookie = table.concat(parts, "; ") }, query = {} }, writer)
        local set = writer.headers["Set-Cookie"]
        if type(set) == "string" then set = { set } end
        for _, header in ipairs(set or {}) do
            local name, value = header:match("^([^=]+)=([^;]*)")
            if header:find("Max-Age=0", 1, true) then jar[name] = nil else jar[name] = value end
        end
        writer.set_cookies = set or {}
        return writer
    end
    function agent.get(path) return agent.request("GET", path) end
    agent.jar = jar
    return agent
end

local function cookie_store_round_trip()
    local agent = browser(new_app())
    local first = agent.get("/set/user/ada")
    tests.assertEquals(#first.set_cookies, 1)
    local header = first.set_cookies[1]
    tests.assertContains(header, "crescent_session=")
    tests.assertContains(header, "HttpOnly")
    tests.assertContains(header, "Secure")
    tests.assertContains(header, "SameSite=Lax")
    tests.assertNotContains(header, "ada", "the payload is encrypted")
    tests.assertEquals(agent.get("/get/user").body, "ada")
end

local function unchanged_session_writes_no_cookie()
    local agent = browser(new_app())
    tests.assertEquals(#agent.get("/noop").set_cookies, 0, "a new, untouched session sets nothing")
    agent.get("/set/a/1")
    tests.assertEquals(#agent.get("/get/a").set_cookies, 0, "reading does not rewrite the cookie")
end

local function tampered_cookie_is_rejected()
    local agent = browser(new_app())
    agent.get("/set/role/user")
    local raw = Base64.url_decode(agent.jar.crescent_session)
    local flipped = raw:sub(1, -2) .. string.char((raw:byte(-1) + 1) % 256)
    agent.jar.crescent_session = Base64.url_encode(flipped)
    local writer = agent.get("/get/role")
    tests.assertEquals(writer.body, "nil")
    tests.assertContains(writer.set_cookies[1], "Max-Age=0", "an invalid cookie is cleared")

    agent.jar.crescent_session = "garbage"
    tests.assertEquals(agent.get("/get/role").body, "nil")
end

local function cookie_is_bound_to_name_and_key()
    local sealed = Session._seal(SECRET, '{"d":{"x":1},"c":1,"a":1}', "crescent_session")
    tests.assertNotNil(Session._unseal({ SECRET }, sealed, "crescent_session"))
    tests.assertNil(Session._unseal({ SECRET }, sealed, "other_cookie"))
    tests.assertNil(Session._unseal({ OLD_SECRET }, sealed, "crescent_session"))
    tests.assertNotNil(Session._unseal({ OLD_SECRET, SECRET }, sealed, "crescent_session"), "fallback keys decrypt")
end

local function key_rotation()
    local old_agent = browser(new_app(nil, { secret_key = OLD_SECRET }))
    old_agent.get("/set/user/ada")
    local rotated = browser(new_app(nil, { secret_key_fallbacks = { OLD_SECRET } }))
    rotated.jar.crescent_session = old_agent.jar.crescent_session
    tests.assertEquals(rotated.get("/get/user").body, "ada")
    local unrotated = browser(new_app())
    unrotated.jar.crescent_session = old_agent.jar.crescent_session
    tests.assertEquals(unrotated.get("/get/user").body, "nil")
end

local function expiry()
    clock = 1000000
    local agent = browser(new_app({ max_age = 1000, idle_timeout = 100 }))
    local header = agent.get("/set/user/ada").set_cookies[1]
    tests.assertContains(header, "Max-Age=1000")

    clock = clock + 99
    tests.assertEquals(agent.get("/get/user").body, "ada", "inside the idle window")
    clock = clock + 99
    tests.assertEquals(agent.get("/get/user").body, "ada", "the idle timer was refreshed")
    clock = clock + 100
    tests.assertEquals(agent.get("/get/user").body, "nil", "idle timeout")

    clock = 2000000
    agent.get("/set/user/ada")
    for _ = 1, 12 do
        clock = clock + 90
        agent.get("/get/user")
    end
    tests.assertEquals(agent.get("/get/user").body, "nil", "absolute max_age even when active")
end

local function size_limit()
    local app, logged = new_app()
    app:get("/big", function(ctx)
        ctx.session:set("blob", string.rep("x", 5000))
        return ctx:text(200, "ok")
    end)
    local writer = browser(app).get("/big")
    tests.assertEquals(writer.status, 500)
    tests.assertNil(writer.headers["Set-Cookie"])
    tests.assertContains(logged[1], "4096-byte browser limit")
    tests.assertContains(logged[1], 'store = "shared"')
end

local function flash_messages()
    local app = new_app()
    app:get("/flash", function(ctx)
        ctx.session:flash("notice", "saved")
        return ctx:redirect("/show")
    end)
    app:get("/show", function(ctx) return ctx:text(200, tostring(ctx.session:get_flash("notice"))) end)
    local agent = browser(app)
    agent.get("/flash")
    tests.assertEquals(agent.get("/show").body, "saved")
    tests.assertEquals(agent.get("/show").body, "nil", "flash values live for one request")
end

local function clear_delete_destroy()
    local app = new_app()
    app:get("/delete/{key}", function(ctx) ctx.session:delete(ctx.params.key) return ctx:text(200, "ok") end)
    app:get("/clear", function(ctx) ctx.session:clear() return ctx:text(200, "ok") end)
    app:get("/logout", function(ctx)
        ctx.session:destroy()
        return ctx:text(200, "bye")
    end)
    app:get("/logout-flash", function(ctx)
        ctx.session:destroy()
        ctx.session:flash("notice", "bye")
        return ctx:text(200, "bye")
    end)
    local agent = browser(app)
    agent.get("/set/a/1")
    agent.get("/set/b/2")
    agent.get("/delete/a")
    tests.assertEquals(agent.get("/get/a").body, "nil")
    tests.assertEquals(agent.get("/get/b").body, "2")
    agent.get("/clear")
    tests.assertEquals(agent.get("/get/b").body, "nil")

    agent.get("/set/user/ada")
    local logout = agent.get("/logout")
    tests.assertContains(logout.set_cookies[1], "Max-Age=0")
    tests.assertNil(agent.jar.crescent_session)

    agent.get("/set/user/ada")
    agent.get("/logout-flash")
    tests.assertNotNil(agent.jar.crescent_session, "values set after destroy start a new session")
    tests.assertEquals(agent.get("/get/user").body, "nil")
end

local function shared_store()
    ngx.shared.crescent_sessions:flush_all()
    clock = 3000000
    local app = new_app({ store = "shared", idle_timeout = 600 })
    app:get("/login", function(ctx)
        ctx.session:set("user", "ada")
        ctx.session:regenerate()
        return ctx:text(200, "ok")
    end)
    app:get("/logout", function(ctx) ctx.session:destroy() return ctx:text(200, "ok") end)
    local agent = browser(app)

    agent.get("/set/cart/3")
    local first = agent.jar.crescent_session
    local id = first:match("^([A-Za-z0-9_%-]+)%.")
    tests.assertEquals(#id, 22, "128-bit id, base64url")
    tests.assertNotNil(ngx.shared.crescent_sessions:get("session:" .. id))
    tests.assertEquals(agent.get("/get/cart").body, "3")
    tests.assertEquals(#agent.get("/set/cart/4").set_cookies, 0, "changing data keeps the id and cookie")

    -- Regenerate: new id, same data, old id gone (session fixation).
    agent.get("/login")
    local second = agent.jar.crescent_session
    tests.assertNotEquals(second, first)
    tests.assertNil(ngx.shared.crescent_sessions:get("session:" .. id))
    tests.assertEquals(agent.get("/get/cart").body, "4")
    tests.assertEquals(agent.get("/get/user").body, "ada")

    -- A forged id (bad signature) is ignored.
    local forged = browser(app)
    forged.jar.crescent_session = second:match("^([^.]+)") .. ".AAAA"
    tests.assertEquals(forged.get("/get/user").body, "nil")

    -- TTL is the idle timeout.
    local new_id = second:match("^([^.]+)")
    local ttl = ngx.shared.crescent_sessions:ttl("session:" .. new_id)
    tests.assertTrue(ttl > 590 and ttl <= 600, "ttl " .. tostring(ttl))

    agent.get("/logout")
    tests.assertNil(ngx.shared.crescent_sessions:get("session:" .. new_id))
    tests.assertNil(agent.jar.crescent_session)

    -- A stolen copy of a destroyed session is useless.
    local thief = browser(app)
    thief.jar.crescent_session = second
    tests.assertEquals(thief.get("/get/user").body, "nil")
end

local function regenerate_cookie_store()
    local app = new_app()
    app:get("/login", function(ctx) ctx.session:regenerate() return ctx:text(200, "ok") end)
    local agent = browser(app)
    agent.get("/set/user/ada")
    local before = agent.jar.crescent_session
    agent.get("/login")
    tests.assertNotEquals(agent.jar.crescent_session, before)
    tests.assertEquals(agent.get("/get/user").body, "ada")
end

local function configuration_errors()
    tests.assertError(function() Session.middleware({ store = "redis" }) end, "unknown session store")
    tests.assertError(function() Session.middleware({ store = "shared", dict = "nope" }) end, "lua_shared_dict nope")
    tests.assertError(function() Session.middleware({ secret = "short" }) end, "at least 32")
    tests.assertError(function() Session.middleware({ max_age = -1 }) end, "max_age")
    tests.assertError(function() Session.middleware({ name = "bad name" }) end, "cookie name")

    local Env = require("crescent.env")
    local original_get = Env.get
    Env.get = function() return nil end
    local app, logged = new_app(nil, { secret_key = false })
    local writer = browser(app).get("/noop")
    Env.get = original_get
    tests.assertEquals(writer.status, 500)
    tests.assertContains(logged[1], "APP_KEY")
end

assert(tests.runSuite("Sessions", {
    cookie_store_round_trip = cookie_store_round_trip,
    unchanged_session_writes_no_cookie = unchanged_session_writes_no_cookie,
    tampered_cookie_is_rejected = tampered_cookie_is_rejected,
    cookie_is_bound_to_name_and_key = cookie_is_bound_to_name_and_key,
    key_rotation = key_rotation,
    expiry = expiry,
    size_limit = size_limit,
    flash_messages = flash_messages,
    clear_delete_destroy = clear_delete_destroy,
    shared_store = shared_store,
    regenerate_cookie_store = regenerate_cookie_store,
    configuration_errors = configuration_errors,
}))
