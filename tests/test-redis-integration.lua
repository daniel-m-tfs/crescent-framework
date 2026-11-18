package.path = "./?.lua;./?/init.lua;" .. package.path

-- Runs against a real Redis only when REDIS_TEST_HOST is set:
--   docker run -d --rm -p 127.0.0.1:6390:6379 redis:7.4-alpine
--   REDIS_TEST_HOST=127.0.0.1 REDIS_TEST_PORT=6390 lua cli.lua test redis-integration
-- Uses database REDIS_TEST_DB (default 15) and only keys under a random prefix.
local host = os.getenv("REDIS_TEST_HOST")
if not host or host == "" then
    print("SKIP Redis integration: set REDIS_TEST_HOST (and REDIS_TEST_PORT/REDIS_TEST_PASSWORD/REDIS_TEST_DB) to run")
    return
end

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local Redis = require("crescent.redis")
local Cache = require("crescent.cache")
local Queue = require("crescent.queue")
local Health = require("crescent.health")
local log = require("tests.fixtures.jobs.log")

local config = {
    host = host,
    port = tonumber(os.getenv("REDIS_TEST_PORT") or "6379"),
    password = os.getenv("REDIS_TEST_PASSWORD"),
    database = tonumber(os.getenv("REDIS_TEST_DB") or "15"),
}
local redis = Redis.new(config)
local PREFIX = "crescent_it:" .. tostring(math.random(1e9)) .. ":"

local RECORD = "tests.fixtures.jobs.record"
local FLAKY = "tests.fixtures.jobs.flaky"

local function reset_log()
    log.calls, log.failed = {}, {}
end

local counter = 0
local function new_queue(options)
    counter = counter + 1
    local name = "q" .. counter
    local settings = { driver = "redis", prefix = PREFIX .. "queue:", queue = name, workers = { queues = { name } } }
    for key, value in pairs(options or {}) do settings[key] = value end
    return Queue.new(settings, { redis = redis, logger = function() end }), name
end

local function client_commands()
    tests.assertTrue(redis:ping())
    tests.assertEquals(redis:command("set", PREFIX .. "k", "v"), "OK")
    tests.assertEquals(redis:command("get", PREFIX .. "k"), "v")
    tests.assertNil(redis:command("get", PREFIX .. "missing"))
    tests.assertEquals(redis:eval("return redis.call('get', KEYS[1])", { PREFIX .. "k" }), "v")
    local results = redis:with(function(red)
        red:init_pipeline()
        red:incr(PREFIX .. "n")
        red:incr(PREFIX .. "n")
        return red:commit_pipeline()
    end)
    tests.assertTableEquals(results, { 1, 2 })
    -- Raised errors propagate (and close the connection).
    tests.assertError(function() redis:with(function() error("inside") end) end, "inside")
    tests.assertTrue(redis:ping())
end

local function selects_the_database()
    redis:command("set", PREFIX .. "db", "here")
    local other = Redis.new({ host = config.host, port = config.port, password = config.password,
        database = config.database == 0 and 1 or 0 })
    tests.assertNil(other:command("get", PREFIX .. "db"))
    tests.assertEquals(redis:command("get", PREFIX .. "db"), "here")
end

local function connection_errors_are_returned()
    local down = Redis.new({ host = "127.0.0.1", port = 1, connect_timeout = 200 })
    local ok, err = down:ping()
    tests.assertNil(ok)
    tests.assertContains(err, "redis: connect failed")
    if config.password then
        local wrong = Redis.new({ host = config.host, port = config.port, password = "wrong-password" })
        local _, auth_err = wrong:ping()
        tests.assertContains(auth_err, "auth failed")
    end
end

local function cache_driver()
    local cache = Cache.new({ driver = "redis", prefix = PREFIX .. "cache:" }, { redis = redis })
    tests.assertTrue(cache:set("user", { id = 1, name = "ada" }, 60))
    tests.assertTableEquals(cache:get("user"), { id = 1, name = "ada" })
    tests.assertTrue(cache:add("once", 1))
    tests.assertFalse(cache:add("once", 2))
    tests.assertEquals(cache:incr("hits", 2, 60), 2)
    tests.assertEquals(cache:incr("hits", 3), 5)
    tests.assertEquals(cache:get("hits"), 5)
    local ttl = redis:command("pttl", PREFIX .. "cache:hits")
    tests.assertTrue(ttl > 0 and ttl <= 60000)
    cache:set("short", "x", 0.1)
    ngx.sleep(0.2)
    tests.assertNil(cache:get("short"))
    tests.assertEquals(cache:remember("r", 60, function() return "computed" end), "computed")
    tests.assertEquals(cache:remember("r", 60, function() return "again" end), "computed")
    -- flush only touches the cache prefix
    redis:command("set", PREFIX .. "outside", "keep")
    tests.assertTrue(cache:flush())
    tests.assertNil(cache:get("user"))
    tests.assertEquals(redis:command("get", PREFIX .. "outside"), "keep")
end

local function queue_push_and_process()
    reset_log()
    local queue, name = new_queue()
    queue:push(RECORD, { n = 1 })
    queue:push(RECORD, { n = 2 })
    tests.assertEquals(queue:size(name).ready, 2)
    tests.assertEquals(queue:work({ stop_when_empty = true }), 2)
    tests.assertEquals(log.calls[1].payload.n, 1)
    tests.assertEquals(log.calls[2].payload.n, 2)
    local size = queue:size(name)
    tests.assertEquals(size.ready + size.reserved + size.delayed, 0)
    tests.assertEquals(redis:command("hlen", PREFIX .. "queue:{" .. name .. "}:attempts"), 0)
end

local function queue_delay_and_retries()
    reset_log()
    local queue, name = new_queue()
    queue:push(RECORD, { late = true }, { delay = 0.3 })
    tests.assertEquals(queue:size(name).delayed, 1)
    tests.assertFalse(queue:work_once())
    ngx.sleep(0.4)
    tests.assertTrue(queue:work_once())

    reset_log()
    queue:push(FLAKY, { succeed_on = 3 })
    queue:work({ stop_when_empty = true })
    tests.assertEquals(#log.calls, 3)
    tests.assertEquals(log.calls[3].attempts, 3)
end

local function queue_failed_jobs()
    reset_log()
    local queue, name = new_queue({ attempts = 2 })
    local id = queue:push(FLAKY, { succeed_on = 9 })
    queue:work({ stop_when_empty = true })
    tests.assertEquals(#log.failed, 1)
    local failed = queue:failed(name)
    tests.assertEquals(#failed, 1)
    tests.assertEquals(failed[1].id, id)
    tests.assertEquals(failed[1].attempts, 2)
    tests.assertContains(failed[1].error, "attempt 2 failed")
    tests.assertEquals(queue:retry(name, id), 1)
    tests.assertEquals(queue:size(name).ready, 1)
    reset_log()
    queue:work({ stop_when_empty = true })
    tests.assertEquals(log.calls[1].attempts, 1)
    tests.assertEquals(queue:clear_failed(name), 1)
    tests.assertEquals(queue:size(name).failed, 0)
end

-- A worker that dies mid-job leaves it reserved; it comes back after the
-- timeout and counts as an attempt.
local function expired_reservations_are_redelivered()
    reset_log()
    local queue, name = new_queue()
    queue:push(RECORD, { n = 1 }, { timeout = 0.2, attempts = 2 })
    local raw, attempts = queue.driver:pop(name, ngx.now())
    tests.assertNotNil(raw)
    tests.assertEquals(attempts, 1)
    tests.assertEquals(queue:size(name).reserved, 1)
    tests.assertFalse(queue:work_once())
    ngx.sleep(0.3)
    tests.assertTrue(queue:work_once())
    tests.assertEquals(log.calls[1].attempts, 2)

    -- Out of attempts after another lost reservation: failed without running.
    reset_log()
    queue:push(RECORD, { n = 2 }, { timeout = 0.2, attempts = 1 })
    queue.driver:pop(name, ngx.now())
    ngx.sleep(0.3)
    queue:work_once()
    tests.assertEquals(#log.calls, 0)
    tests.assertContains(queue:failed(name)[1].error, "exceeded 1 attempt")
end

local function app_with_redis_drivers()
    reset_log()
    local app = Crescent.new({
        logger = function() end,
        redis = config,
        cache = { driver = "redis", prefix = PREFIX .. "app:cache:" },
        queue = { driver = "redis", prefix = PREFIX .. "app:queue:" },
    })
    tests.assertNotNil(app.redis)
    tests.assertFalse(app.queue.settings.workers.embedded)
    Health.register(app)
    app:post("/jobs", function(ctx)
        ctx.cache:set("last", "job")
        return ctx:json(202, { id = ctx.queue:push(RECORD, { via = "http" }) })
    end)
    local writer = { headers = {}, sent = false }
    app:handle({ method = "POST", path = "/jobs", headers = {}, query = {} }, writer)
    tests.assertEquals(writer.status, 202)
    tests.assertEquals(app.cache:get("last"), "job")
    tests.assertEquals(app.queue:work({ stop_when_empty = true }), 1)
    tests.assertEquals(log.calls[1].payload.via, "http")

    local ready = { headers = {}, sent = false }
    app:handle({ method = "GET", path = "/ready", headers = {}, query = {} }, ready)
    tests.assertEquals(ready.status, 200)
    tests.assertContains(ready.body, '"redis"')
end

local function cleanup()
    redis:with(function(red)
        local cursor = "0"
        repeat
            local reply = red:scan(cursor, "MATCH", PREFIX .. "*", "COUNT", 500)
            cursor = reply[1]
            if #reply[2] > 0 then red:del(unpack(reply[2])) end
        until cursor == "0"
    end)
end

local ok = tests.runSuite("Redis integration", {
    ["client commands, eval and pipelines"] = client_commands,
    ["selects the configured database"] = selects_the_database,
    ["connection errors are returned"] = connection_errors_are_returned,
    ["cache redis driver"] = cache_driver,
    ["queue push and process (FIFO)"] = queue_push_and_process,
    ["queue delay and retries"] = queue_delay_and_retries,
    ["queue failed jobs"] = queue_failed_jobs,
    ["expired reservations are redelivered"] = expired_reservations_are_redelivered,
    ["app with redis drivers"] = app_with_redis_drivers,
})
cleanup()
assert(ok)
