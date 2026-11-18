package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local Queue = require("crescent.queue")
local log = require("tests.fixtures.jobs.log")

local RECORD = "tests.fixtures.jobs.record"
local FLAKY = "tests.fixtures.jobs.flaky"

local counter = 0
local function unique_queue()
    counter = counter + 1
    return "q" .. counter .. "_" .. tostring(math.random(1e9))
end

local function reset_log()
    log.calls, log.failed = {}, {}
end

local function new_queue(config)
    local logged = {}
    local name = unique_queue()
    local settings = { queue = name, workers = { queues = { name } } }
    for key, value in pairs(config or {}) do
        if key == "workers" then
            for option, setting in pairs(value) do settings.workers[option] = setting end
        else
            settings[key] = value
        end
    end
    local queue = Queue.new(settings, { logger = function(level, message) logged[#logged + 1] = level .. ": " .. message end })
    return queue, name, logged
end

local function push_and_process()
    reset_log()
    local queue, name = new_queue()
    local id = queue:push(RECORD, { user_id = 7, tags = { "x" } })
    tests.assertIsString(id)
    tests.assertEquals(queue:size(name).ready, 1)
    tests.assertTrue(queue:work_once())
    tests.assertEquals(#log.calls, 1)
    tests.assertTableEquals(log.calls[1].payload, { user_id = 7, tags = { "x" } })
    tests.assertEquals(log.calls[1].attempts, 1)
    tests.assertEquals(log.calls[1].queue, name)
    tests.assertEquals(log.calls[1].id, id)
    tests.assertFalse(queue:work_once())
    tests.assertEquals(queue:size(name).ready, 0)
end

local function fifo_order()
    reset_log()
    local queue = new_queue()
    for index = 1, 3 do queue:push(RECORD, { n = index }) end
    tests.assertEquals(queue:work({ stop_when_empty = true }), 3)
    tests.assertEquals(log.calls[1].payload.n, 1)
    tests.assertEquals(log.calls[3].payload.n, 3)
end

local function delayed_jobs_wait()
    reset_log()
    local queue, name = new_queue()
    queue:push(RECORD, { late = true }, { delay = 0.2 })
    tests.assertEquals(queue:size(name).delayed, 1)
    tests.assertFalse(queue:work_once())
    ngx.sleep(0.6)
    tests.assertTrue(queue:work_once())
    tests.assertEquals(log.calls[1].payload.late, true)
end

local function retries_then_succeeds()
    reset_log()
    local queue, _, logged = new_queue()
    queue:push(FLAKY, { succeed_on = 3 })
    tests.assertEquals(queue:work({ stop_when_empty = true }), 3)
    tests.assertEquals(#log.calls, 3)
    tests.assertEquals(log.calls[3].attempts, 3)
    tests.assertEquals(#log.failed, 0)
    tests.assertContains(logged[1], "warn: job attempt failed, retrying")
end

local function soft_failure_retries()
    reset_log()
    local queue = new_queue()
    queue:push(FLAKY, { succeed_on = 2, soft = true })
    queue:work({ stop_when_empty = true })
    tests.assertEquals(#log.calls, 2)
end

local function gives_up_after_max_attempts()
    reset_log()
    local queue, name, logged = new_queue()
    local id = queue:push(FLAKY, { succeed_on = 99 }, { attempts = 2 })
    queue:work({ stop_when_empty = true })
    tests.assertEquals(#log.calls, 2)
    tests.assertEquals(#log.failed, 1)
    tests.assertContains(log.failed[1].err, "attempt 2 failed")
    tests.assertEquals(log.failed[1].payload.succeed_on, 99)
    tests.assertContains(logged[#logged], "error: job failed")

    local failed = queue:failed(name)
    tests.assertEquals(#failed, 1)
    tests.assertEquals(failed[1].id, id)
    tests.assertEquals(failed[1].name, FLAKY)
    tests.assertEquals(failed[1].attempts, 2)
    tests.assertEquals(failed[1].payload.succeed_on, 99)
    tests.assertContains(failed[1].error, "attempt 2 failed")
    tests.assertEquals(queue:size(name).failed, 1)
end

local function retry_and_clear_failed()
    reset_log()
    local queue, name = new_queue({ attempts = 1 })
    local first = queue:push(FLAKY, { succeed_on = 2 })
    queue:push(FLAKY, { succeed_on = 2 })
    queue:work({ stop_when_empty = true })
    tests.assertEquals(queue:size(name).failed, 2)

    -- Retried jobs start over with attempts reset.
    tests.assertEquals(queue:retry(name, first), 1)
    tests.assertEquals(queue:size(name).failed, 1)
    tests.assertEquals(queue:size(name).ready, 1)
    reset_log()
    queue:work({ stop_when_empty = true })
    tests.assertEquals(log.calls[1].attempts, 1)
    tests.assertEquals(queue:retry(name, "nope"), 0)
    tests.assertEquals(queue:clear_failed(name), 2)
    tests.assertEquals(queue:size(name).failed, 0)
end

local function failed_list_is_capped()
    local queue, name = new_queue({ attempts = 1, failed_limit = 2 })
    for _ = 1, 4 do queue:push(FLAKY, { succeed_on = 9 }) end
    queue:work({ stop_when_empty = true })
    tests.assertEquals(queue:size(name).failed, 2)
end

local function unknown_job_names_are_rejected()
    local queue = new_queue()
    tests.assertError(function() queue:push("tests.fixtures.jobs.missing", {}) end, "unable to load job")
    tests.assertError(function() queue:push("tests.fixtures.jobs.not_a_job", {}) end, "handle(payload, job)")
    tests.assertError(function() queue:push("../etc/passwd", {}) end, "invalid job name")
    tests.assertError(function() queue:push(RECORD, { fn = function() end }) end, "JSON")
    tests.assertError(function() queue:push(RECORD, {}, { delay = -1 }) end, "delay")
    tests.assertError(function() queue:push(RECORD, {}, { queue = "bad name" }) end, "invalid queue name")
end

local function job_options_come_from_the_module()
    reset_log()
    local queue = new_queue()
    local mail = unique_queue()
    package.loaded["tests.fixtures.jobs.mail_job"] = {
        queue = mail,
        handle = function(_, job) log.calls[#log.calls + 1] = { queue = job.queue, max = job.max_attempts } end,
    }
    queue:push("tests.fixtures.jobs.mail_job", {}, { attempts = 4 })
    tests.assertEquals(queue:size(mail).ready, 1)
    queue:work({ queues = { mail }, stop_when_empty = true })
    tests.assertEquals(log.calls[1].queue, mail)
    tests.assertEquals(log.calls[1].max, 4)
end

local function jobs_can_dispatch_jobs()
    reset_log()
    local queue, name = new_queue()
    queue:push("tests.fixtures.jobs.chain", { queue = name })
    tests.assertEquals(queue:work({ stop_when_empty = true }), 2)
    tests.assertIsString(log.calls[1].payload.from)
end

local function broken_job_module_fails_the_job()
    local queue, name = new_queue()
    queue:push(RECORD, {})
    package.loaded[RECORD] = nil
    package.preload[RECORD] = function() error("syntax error near x") end
    queue:work({ stop_when_empty = true })
    package.preload[RECORD] = nil
    tests.assertEquals(queue:size(name).failed, 1)
    tests.assertContains(queue:failed(name)[1].error, "syntax error near x")
    require(RECORD)
end

local function sync_driver_runs_immediately()
    reset_log()
    local queue = Queue.new({ driver = "sync" })
    queue:push(RECORD, { now = true })
    tests.assertEquals(#log.calls, 1)
    tests.assertEquals(log.calls[1].payload.now, true)
    tests.assertError(function() queue:push(FLAKY, { succeed_on = 2 }) end, "attempt 1 failed")
    tests.assertEquals(#log.failed, 1)
    tests.assertEquals(queue:start_embedded(), 0)
end

local function backend_errors_back_off()
    local calls = 0
    local driver = { pop = function() calls = calls + 1 return nil, "redis: connect failed" end }
    local logged = {}
    local queue = Queue.new({ workers = { sleep = 0.01, max_sleep = 0.02 } },
        { driver = driver, logger = function(level, message) logged[#logged + 1] = level .. ": " .. message end })
    queue:work({ max_time = 0.1 })
    tests.assertTrue(calls >= 2)
    tests.assertContains(logged[1], "error: queue worker: redis: connect failed")
end

local function embedded_workers_process_in_background()
    reset_log()
    local queue, name = new_queue({ workers = { sleep = 0.05, concurrency = 2 } })
    tests.assertTrue(queue.settings.workers.embedded)
    tests.assertEquals(queue:start_embedded(), 2)
    queue:push(RECORD, { background = true })
    for _ = 1, 40 do
        if #log.calls > 0 then break end
        ngx.sleep(0.05)
    end
    tests.assertEquals(#log.calls, 1)
    tests.assertEquals(queue:size(name).ready, 0)
end

local function config_validation()
    tests.assertError(function() Queue.new({ driver = "kafka" }) end, "unknown queue driver")
    tests.assertError(function() Queue.new({ driver = "redis" }) end, "requires config.redis")
    tests.assertError(function() Queue.new({ attempts = 0 }) end, "attempts")
    tests.assertError(function() Queue.new({ backoff = { -1 } }) end, "backoff")
    tests.assertFalse(Queue.new({ driver = "redis" }, { redis = {} }).settings.workers.embedded)
end

local function app_exposes_queue_on_ctx()
    reset_log()
    local app = Crescent.new({ queue = { driver = "sync" }, logger = function() end })
    app:post("/signup", function(ctx)
        ctx.queue:push(RECORD, { email = "ada@example.com" })
        return ctx:json(202, { queued = true })
    end)
    local writer = { headers = {}, sent = false }
    app:handle({ method = "POST", path = "/signup", headers = {}, query = {} }, writer)
    tests.assertEquals(writer.status, 202)
    tests.assertEquals(log.calls[1].payload.email, "ada@example.com")
    tests.assertEquals(app:start_workers(), 0)
    tests.assertEquals(Crescent.new({ logger = function() end }):start_workers(), 0)
end

local function job_context_carries_app_services()
    local seen
    package.loaded["tests.fixtures.jobs.inspect"] = { handle = function(_, job) seen = job end }
    local app = Crescent.new({ queue = { driver = "sync" }, cache = {}, logger = function() end })
    app.queue:push("tests.fixtures.jobs.inspect", {})
    tests.assertEquals(seen.app, app)
    tests.assertEquals(seen.cache, app.cache)
    tests.assertIsFunction(seen.dispatch)
    tests.assertIsFunction(seen.log)
end

local function development_workers_reload_app_modules()
    local app = Crescent.new({ debug = true, queue = {}, logger = function() end })
    tests.assertTrue(app.queue.settings.workers.reload)
    local production = Crescent.new({ debug = false, queue = {}, logger = function() end })
    tests.assertFalse(production.queue.settings.workers.reload)
    package.loaded["src.fake_module"] = true
    Queue.load_job(RECORD, true)
    tests.assertNil(package.loaded["src.fake_module"])
end

local function cli_option_parsing()
    local QueueCommand = require("cli.commands.queue")
    local options, positional = QueueCommand.parse({ "--queue=mail,default", "--once", "abc", "--max-jobs=5" })
    tests.assertTableEquals(options, { queue = "mail,default", once = true, ["max-jobs"] = "5" })
    tests.assertTableEquals(positional, { "abc" })
end

assert(tests.runSuite("Queue", {
    ["CLI option parsing"] = cli_option_parsing,
    ["push and process"] = push_and_process,
    ["FIFO order"] = fifo_order,
    ["delayed jobs wait"] = delayed_jobs_wait,
    ["retries then succeeds"] = retries_then_succeeds,
    ["returning false retries"] = soft_failure_retries,
    ["gives up after max attempts"] = gives_up_after_max_attempts,
    ["retry and clear failed jobs"] = retry_and_clear_failed,
    ["failed list is capped"] = failed_list_is_capped,
    ["rejects invalid jobs and options"] = unknown_job_names_are_rejected,
    ["job module provides defaults"] = job_options_come_from_the_module,
    ["jobs can dispatch jobs"] = jobs_can_dispatch_jobs,
    ["a broken job module fails the job"] = broken_job_module_fails_the_job,
    ["sync driver runs immediately"] = sync_driver_runs_immediately,
    ["backend errors back off"] = backend_errors_back_off,
    ["embedded workers run in the background"] = embedded_workers_process_in_background,
    ["config validation"] = config_validation,
    ["app exposes ctx.queue"] = app_exposes_queue_on_ctx,
    ["job context carries app services"] = job_context_carries_app_services,
    ["development workers reload app modules"] = development_workers_reload_app_modules,
}))
