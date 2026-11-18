package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local Cache = require("crescent.cache")
local Health = require("crescent.health")

local function new_cache(config)
    local settings = { prefix = "t:" .. tostring(math.random(1e9)) .. ":" }
    for key, value in pairs(config or {}) do settings[key] = value end
    return Cache.new(settings)
end

local function stores_json_values()
    local cache = new_cache()
    tests.assertTrue(cache:set("table", { name = "ada", tags = { "a", "b" } }))
    tests.assertTableEquals(cache:get("table"), { name = "ada", tags = { "a", "b" } })
    cache:set("string", "text")
    tests.assertEquals(cache:get("string"), "text")
    cache:set("number", 42.5)
    tests.assertEquals(cache:get("number"), 42.5)
    cache:set("false", false)
    tests.assertEquals(cache:get("false"), false)
    tests.assertTrue(cache:has("false"))
    tests.assertNil(cache:get("missing"))
    tests.assertEquals(cache:get("missing", "fallback"), "fallback")
end

local function rejects_nil_and_bad_keys()
    local cache = new_cache()
    tests.assertError(function() cache:set("key", nil) end, "cannot cache nil")
    tests.assertError(function() cache:set("", 1) end, "non-empty string")
    tests.assertError(function() cache:set("key", function() end) end, "JSON")
    tests.assertError(function() cache:set("key", 1, -1) end, "ttl")
end

local function expires_entries()
    local cache = new_cache()
    cache:set("short", "value", 0.05)
    tests.assertEquals(cache:get("short"), "value")
    ngx.sleep(0.1)
    tests.assertNil(cache:get("short"))
    cache:set("forever", "value", 0)
    tests.assertEquals(cache:get("forever"), "value")
end

local function add_delete_pull()
    local cache = new_cache()
    tests.assertTrue(cache:add("once", 1))
    tests.assertFalse(cache:add("once", 2))
    tests.assertEquals(cache:get("once"), 1)
    tests.assertEquals(cache:pull("once"), 1)
    tests.assertNil(cache:get("once"))
    cache:set("gone", true)
    cache:forget("gone")
    tests.assertFalse(cache:has("gone"))
end

local function counters()
    local cache = new_cache()
    tests.assertEquals(cache:incr("hits"), 1)
    tests.assertEquals(cache:incr("hits", 5), 6)
    tests.assertEquals(cache:decr("hits", 2), 4)
    tests.assertEquals(cache:get("hits"), 4)
end

local function remember_computes_once()
    local cache = new_cache()
    local calls = 0
    local function compute()
        calls = calls + 1
        return { value = calls }
    end
    tests.assertTableEquals(cache:remember("r", 60, compute), { value = 1 })
    tests.assertTableEquals(cache:remember("r", 60, compute), { value = 1 })
    tests.assertEquals(calls, 1)
    -- ttl is optional
    tests.assertEquals(cache:remember("r2", function() return "x" end), "x")
    -- nil is returned but not cached
    local nil_calls = 0
    cache:remember("nil", 60, function() nil_calls = nil_calls + 1 end)
    cache:remember("nil", 60, function() nil_calls = nil_calls + 1 end)
    tests.assertEquals(nil_calls, 2)
    -- errors propagate and release the lock
    tests.assertError(function() cache:remember("boom", 60, function() error("kaput") end) end, "kaput")
    tests.assertEquals(cache:remember("boom", 60, function() return "ok" end), "ok")
end

local function remember_waits_for_concurrent_computation()
    local cache = new_cache()
    local calls = 0
    local function slow()
        calls = calls + 1
        ngx.sleep(0.1)
        return "computed"
    end
    local results = {}
    local threads = {}
    for index = 1, 3 do
        threads[index] = ngx.thread.spawn(function() results[index] = cache:remember("stampede", 60, slow) end)
    end
    for _, thread in ipairs(threads) do ngx.thread.wait(thread) end
    tests.assertEquals(calls, 1)
    tests.assertTableEquals(results, { "computed", "computed", "computed" })
end

local function flush_clears_the_dict()
    local cache = new_cache()
    cache:set("a", 1)
    cache:set("b", 2)
    tests.assertTrue(cache:flush())
    tests.assertNil(cache:get("a"))
    tests.assertNil(cache:get("b"))
end

local function missing_dict_has_a_clear_error()
    local cache = new_cache({ dict = "no_such_dict" })
    tests.assertError(function() cache:get("x") end, "lua_shared_dict no_such_dict")
end

local function config_validation()
    tests.assertError(function() Cache.new({ driver = "memcached" }) end, "unknown cache driver")
    tests.assertError(function() Cache.new({ driver = "redis" }) end, "requires config.redis")
end

-- A custom driver can stand in for any backend.
local function backend_errors_degrade_to_misses()
    local failing = {
        get = function() return nil, "connection refused" end,
        set = function() return nil, "connection refused" end,
        add = function() return nil, "connection refused" end,
        delete = function() return nil, "connection refused" end,
    }
    local cache = Cache.new({ prefix = "x:" }, { driver = failing })
    local value, err = cache:get("key")
    tests.assertNil(value)
    tests.assertEquals(err, "connection refused")
    tests.assertEquals(cache:remember("key", 60, function() return "fresh" end), "fresh")
end

local function app_exposes_cache_on_ctx()
    local app = Crescent.new({ cache = { prefix = "app:" }, logger = function() end })
    tests.assertNotNil(app.cache)
    tests.assertNil(app.redis)
    app:get("/count", function(ctx)
        return ctx:json(200, { count = ctx.cache:incr("count") })
    end)
    local writer = { headers = {}, sent = false }
    app:handle({ method = "GET", path = "/count", headers = {}, query = {} }, writer)
    tests.assertContains(writer.body, '"count":')
    tests.assertNil(Crescent.new({ logger = function() end }).cache)
end

local function redis_client_only_when_used()
    local redis = { host = "127.0.0.1" }
    tests.assertNil(Crescent.new({ redis = redis, cache = { driver = "shared" }, logger = function() end }).redis)
    local app = Crescent.new({ redis = redis, cache = { driver = "redis" }, logger = function() end })
    tests.assertNotNil(app.redis)
    tests.assertNotNil(Crescent.new({ redis = { host = "x", enabled = true }, logger = function() end }).redis)
end

local function ready_checks_redis_when_configured()
    local app = Crescent.new({ logger = function() end, redis_client = {
        ping = function() return nil, "redis: connect failed: connection refused" end,
    } })
    Health.register(app)
    local writer = { headers = {}, sent = false }
    app:handle({ method = "GET", path = "/ready", headers = {}, query = {} }, writer)
    tests.assertEquals(writer.status, 503)
    tests.assertContains(writer.body, '"redis"')
end

assert(tests.runSuite("Cache", {
    ["stores JSON values"] = stores_json_values,
    ["rejects nil values and bad keys"] = rejects_nil_and_bad_keys,
    ["expires entries"] = expires_entries,
    ["add, delete and pull"] = add_delete_pull,
    ["atomic counters"] = counters,
    ["remember computes once"] = remember_computes_once,
    ["remember waits for a concurrent computation"] = remember_waits_for_concurrent_computation,
    ["flush clears the dict"] = flush_clears_the_dict,
    ["missing dict has a clear error"] = missing_dict_has_a_clear_error,
    ["config validation"] = config_validation,
    ["backend errors degrade to misses"] = backend_errors_degrade_to_misses,
    ["app exposes ctx.cache"] = app_exposes_cache_on_ctx,
    ["redis client only when a driver uses it"] = redis_client_only_when_used,
    ["/ready checks redis"] = ready_checks_redis_when_configured,
}))
