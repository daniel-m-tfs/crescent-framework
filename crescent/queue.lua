-- Background jobs, exposed as `ctx.queue` / `app.queue` when config.queue is
-- set:
--
--   queue = {
--       driver = "shared",            -- "redis" (config.redis) or "sync"
--       prefix = "myapp:queue:",      -- redis key namespace
--       attempts = 3, backoff = { 10, 60, 300 }, timeout = 60,
--       workers = { embedded = true, concurrency = 1, queues = { "default" }, sleep = 1 },
--   }
--
-- A job is a Lua module with handle(payload, job); its name is the module
-- path, so any process can load it without a registry:
--
--   -- src/users/jobs/send_welcome.lua
--   local SendWelcome = { queue = "mail", attempts = 5, backoff = 30, timeout = 120 }
--   function SendWelcome.handle(payload, job)
--       local user = User:find(payload.user_id)       -- job.db, job.cache, job.app ...
--       ...                                           -- error() or `return false, err` retries
--   end
--   function SendWelcome.failed(payload, err, job) end  -- optional, after the last attempt
--   return SendWelcome
--
--   ctx.queue:push("src.users.jobs.send_welcome", { user_id = user.id })
--   ctx.queue:push("src.users.jobs.send_welcome", payload, { delay = 60, queue = "mail" })
--
-- Drivers:
--   shared  in the memory of one OpenResty server (lua_shared_dict
--           crescent_queue), processed by workers embedded in the nginx
--           workers. No extra service; jobs are lost on restart.
--   redis   durable, shared by every server; processed by `lua cli.lua
--           queue:work` (a separate process/container) or embedded workers.
--   sync    runs the job immediately inside push() (tests, scripts); errors
--           propagate to the caller.
-- Delivery is at-least-once: a job may run again after a crash or timeout,
-- so handlers should be idempotent. The payload must be JSON-serializable.
local json = require("crescent.json")

local Queue = {}
Queue.__index = Queue

local DEFAULTS = {
    driver = "shared",
    prefix = "crescent:queue:",
    dict = "crescent_queue",
    queue = "default",
    attempts = 3,
    backoff = { 10, 60, 300 },
    timeout = 60,
    failed_limit = 1000,
}

local WORKER_DEFAULTS = {
    concurrency = 1,
    queues = { "default" },
    sleep = 1,
    max_sleep = 30,
}

local DRIVERS = {
    shared = "crescent.queue.shared",
    redis = "crescent.queue.redis",
}

local function now()
    if ngx and ngx.now then
        ngx.update_time()
        return ngx.now()
    end
    return os.time()
end

local function sleep(seconds)
    if ngx and ngx.sleep then return ngx.sleep(seconds) end
    error("queue workers need the OpenResty runtime (ngx.sleep)")
end

local function new_id()
    local Crypto = require("crescent.security.crypto")
    return require("crescent.security.base64").url_encode(Crypto.random_bytes(12))
end

local function copy(source)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    return result
end

local function valid_backoff(value)
    if type(value) == "number" then return value >= 0 end
    if type(value) ~= "table" or #value == 0 then return false end
    for _, delay in ipairs(value) do
        if type(delay) ~= "number" or delay < 0 then return false end
    end
    return true
end

-- options.redis: a crescent.redis client (redis driver); options.logger:
-- function(level, message, fields); options.driver: a custom driver object.
function Queue.new(config, options)
    config = config or {}
    options = options or {}
    if type(config) ~= "table" then error("queue config must be a table", 2) end
    local settings = copy(DEFAULTS)
    for key, value in pairs(config) do settings[key] = value end
    if type(settings.attempts) ~= "number" or settings.attempts < 1 then error("queue attempts must be >= 1", 2) end
    if type(settings.timeout) ~= "number" or settings.timeout <= 0 then error("queue timeout must be > 0", 2) end
    if not valid_backoff(settings.backoff) then error("queue backoff must be seconds or a list of seconds", 2) end

    local workers = copy(WORKER_DEFAULTS)
    for key, value in pairs(config.workers or {}) do workers[key] = value end
    -- The shared driver is only reachable from inside OpenResty, so its
    -- workers run there by default; redis gets a dedicated worker process.
    if workers.embedded == nil then workers.embedded = settings.driver == "shared" end
    settings.workers = workers

    local driver = options.driver
    if not driver and settings.driver ~= "sync" then
        local module = DRIVERS[settings.driver]
        if not module then error("unknown queue driver: " .. tostring(settings.driver), 2) end
        driver = require(module).new(settings, options.redis)
    end
    return setmetatable({
        settings = settings,
        driver = driver,
        logger = options.logger,
        app = options.app,
    }, Queue)
end

function Queue:log(level, message, fields)
    if self.logger then return self.logger(level, message, fields) end
    if ngx and ngx.log then
        local levels = { error = ngx.ERR, warn = ngx.WARN, info = ngx.INFO, debug = ngx.DEBUG }
        ngx.log(levels[level] or ngx.NOTICE, message)
    end
end

-- Jobs ----------------------------------------------------------------------

function Queue.valid_name(name)
    return type(name) == "string" and name:match("^[%a_][%w_]*[%w_%.]*$") ~= nil and not name:find("..", 1, true)
end

-- Loads a job module; `fresh` drops cached app modules (src.*) first, so a
-- development worker picks up code changes like lua_code_cache off does.
function Queue.load_job(name, fresh)
    if not Queue.valid_name(name) then return nil, "invalid job name: " .. tostring(name) end
    if fresh then
        for module in pairs(package.loaded) do
            if module:match("^src%.") then package.loaded[module] = nil end
        end
    end
    local ok, job = pcall(require, name)
    if not ok then
        -- A failed require leaves a sentinel that turns every later require
        -- into "loop or previous error"; drop it so a fix can be retried.
        if type(package.loaded[name]) ~= "table" then package.loaded[name] = nil end
        return nil, "unable to load job " .. name .. ": " .. tostring(job)
    end
    if type(job) ~= "table" or type(job.handle) ~= "function" then
        return nil, "job " .. name .. " must return a table with handle(payload, job)"
    end
    return job
end

-- Pushes a job. options: queue, delay (seconds), attempts, backoff, timeout;
-- defaults come from the job module, then config.queue. Returns the job id.
function Queue:push(name, payload, options)
    options = options or {}
    local job, load_err = Queue.load_job(name)
    if not job then error(load_err, 2) end
    local settings = self.settings
    local record = {
        id = new_id(),
        job = name,
        payload = payload == nil and json.empty_array or payload,
        queue = options.queue or job.queue or settings.queue,
        max_attempts = options.attempts or job.attempts or settings.attempts,
        backoff = options.backoff or job.backoff or settings.backoff,
        timeout = options.timeout or job.timeout or settings.timeout,
        created_at = now(),
    }
    if type(record.queue) ~= "string" or not record.queue:match("^[%w_%-%.:]+$") then
        error("invalid queue name: " .. tostring(record.queue), 2)
    end
    if type(record.max_attempts) ~= "number" or record.max_attempts < 1 then error("job attempts must be >= 1", 2) end
    if not valid_backoff(record.backoff) then error("job backoff must be seconds or a list of seconds", 2) end
    local delay = options.delay or 0
    if type(delay) ~= "number" or delay < 0 then error("job delay must be a number >= 0", 2) end

    local raw, encode_err = json.encode(record)
    if not raw then error("job payload is not JSON-serializable: " .. tostring(encode_err), 2) end

    if not self.driver then
        -- Round-trip through JSON like the real drivers do.
        record = json.decode(raw)
        record.attempts = 1
        self:run(job, record)
        return record.id
    end
    local ok, err = self.driver:push(record.queue, raw, delay, now())
    if not ok then return nil, err end
    return record.id
end

Queue.dispatch = Queue.push

-- What a handler receives as its second argument.
function Queue:context(record)
    local app = self.app
    local queue = self
    return {
        id = record.id,
        name = record.job,
        queue = record.queue,
        attempts = record.attempts,
        max_attempts = record.max_attempts,
        app = app,
        db = app and app.db,
        cache = app and app.cache,
        config = app and app.config,
        dispatch = function(name, payload, options) return queue:push(name, payload, options) end,
        log = function(level, message, fields)
            fields = copy(fields)
            fields.job = record.job
            fields.job_id = record.id
            return queue:log(level, message, fields)
        end,
    }
end

-- Runs a sync-driver job; failures call job.failed and are re-raised.
function Queue:run(job, record)
    local context = self:context(record)
    local ok, result, failure = xpcall(job.handle, debug.traceback, record.payload, context)
    if ok and result ~= false then return true end
    local err = ok and tostring(failure or "job returned false") or result
    if job.failed then pcall(job.failed, record.payload, err, context) end
    error(err, 0)
end

local function backoff_for(record, attempts)
    local backoff = record.backoff
    if type(backoff) == "number" then return backoff end
    return backoff[attempts] or backoff[#backoff] or 0
end

-- Processes one reserved job: ack on success, release with backoff while
-- attempts remain, otherwise move it to the failed list.
function Queue:process(raw, attempts)
    local driver = self.driver
    local record = json.decode(raw)
    if type(record) ~= "table" or type(record.id) ~= "string" or type(record.queue) ~= "string" then
        self:log("error", "queue: dropping malformed job", { raw = raw:sub(1, 200) })
        return false
    end
    record.attempts = attempts
    record.max_attempts = tonumber(record.max_attempts) or self.settings.attempts
    record.backoff = valid_backoff(record.backoff) and record.backoff or self.settings.backoff
    local fields = { job = record.job, job_id = record.id, queue = record.queue, attempt = attempts }

    local function fail(err, job, context)
        local entry = json.encode({
            id = record.id, job = raw, name = record.job, queue = record.queue,
            attempts = attempts, error = tostring(err):sub(1, 4000), failed_at = now(),
        })
        local ok, fail_err = driver:fail(record.queue, raw, record, entry)
        if not ok then self:log("error", "queue: unable to store failed job: " .. tostring(fail_err), fields) end
        if job and job.failed then
            local called, callback_err = pcall(job.failed, record.payload, err, context)
            if not called then self:log("error", "queue: failed() callback raised: " .. tostring(callback_err), fields) end
        end
        self:log("error", "job failed: " .. record.job .. ": " .. tostring(err), fields)
        return false
    end

    if attempts > record.max_attempts then
        return fail("exceeded " .. record.max_attempts .. " attempt(s); the last one timed out or its worker stopped")
    end

    local job, load_err = Queue.load_job(record.job, self.settings.workers.reload)
    if not job then return fail(load_err) end

    local context = self:context(record)
    local started = now()
    local ok, result, failure = xpcall(job.handle, debug.traceback, record.payload, context)
    if ok and result ~= false then
        local acked, ack_err = driver:ack(record.queue, raw, record)
        if not acked then self:log("error", "queue: ack failed: " .. tostring(ack_err), fields) end
        fields.duration_ms = math.floor((now() - started) * 1000 + 0.5)
        self:log("info", "job done: " .. record.job, fields)
        return true
    end
    local err = ok and tostring(failure or "job returned false") or result
    if attempts < record.max_attempts then
        local delay = backoff_for(record, attempts)
        local released, release_err = driver:release(record.queue, raw, record, delay, now())
        if not released then self:log("error", "queue: release failed: " .. tostring(release_err), fields) end
        fields.retry_in = delay
        self:log("warn", "job attempt failed, retrying: " .. record.job .. ": " .. tostring(err), fields)
        return false
    end
    return fail(err, job, context)
end

-- Reserves and processes one job from the first non-empty queue.
-- -> true (a job ran), false (all empty) | nil, err (backend error)
function Queue:work_once(queues)
    if not self.driver then return nil, "the sync queue driver has no workers" end
    for _, name in ipairs(queues or self.settings.workers.queues) do
        local raw, attempts = self.driver:pop(name, now())
        if raw then
            self:process(raw, attempts)
            return true
        elseif attempts ~= nil then
            return nil, attempts
        end
    end
    return false
end

-- Worker loop. options: queues, sleep (seconds when idle), max_jobs,
-- max_time (seconds), stop_when_empty, should_stop() -> boolean.
-- Returns the number of jobs processed.
function Queue:work(options)
    options = options or {}
    local workers = self.settings.workers
    local queues = options.queues or workers.queues
    local idle = options.sleep or workers.sleep
    local started, processed, pause = now(), 0, idle
    while true do
        if ngx and ngx.worker and ngx.worker.exiting and ngx.worker.exiting() then break end
        if options.should_stop and options.should_stop() then break end
        if options.max_jobs and processed >= options.max_jobs then break end
        if options.max_time and now() - started >= options.max_time then break end

        local ran, ok, err = pcall(self.work_once, self, queues)
        if not ran then ok, err = nil, ok end
        if ok then
            processed = processed + 1
            pause = idle
        elseif ok == false then
            if options.stop_when_empty then break end
            sleep(idle)
        else
            -- Backend down: back off up to max_sleep instead of spinning.
            self:log("error", "queue worker: " .. tostring(err), { queues = table.concat(queues, ",") })
            sleep(pause)
            pause = math.min(pause * 2, workers.max_sleep)
        end
    end
    return processed
end

-- Starts `workers.concurrency` worker loops in this nginx worker (call from
-- init_worker_by_lua). No-op unless workers.embedded is on.
function Queue:start_embedded()
    local workers = self.settings.workers
    if not workers.embedded or not self.driver then return 0 end
    if not (ngx and ngx.timer and ngx.timer.at) then return 0 end
    local started = 0
    for _ = 1, workers.concurrency do
        local ok, err = ngx.timer.at(0, function(premature)
            if premature then return end
            self:work()
        end)
        if ok then
            started = started + 1
        else
            self:log("error", "queue: unable to start an embedded worker: " .. tostring(err))
        end
    end
    return started
end

-- Monitoring / admin --------------------------------------------------------

function Queue:size(name)
    if not self.driver then return { ready = 0, delayed = 0, reserved = 0, failed = 0 } end
    return self.driver:size(name or self.settings.queue)
end

-- Failed jobs, newest first: { id, name, queue, attempts, error, failed_at, payload }.
function Queue:failed(name, limit)
    if not self.driver then return {} end
    local entries, err = self.driver:failed(name or self.settings.queue, limit or 50)
    if not entries then return nil, err end
    local result = {}
    for _, raw in ipairs(entries) do
        local entry = json.decode(raw)
        if type(entry) == "table" then
            local job = type(entry.job) == "string" and json.decode(entry.job) or nil
            entry.payload = type(job) == "table" and job.payload or nil
            entry.job = nil
            result[#result + 1] = entry
        end
    end
    return result
end

-- Moves failed jobs back to the ready list (all of them when id is nil),
-- with their attempts reset. Returns the number of jobs requeued.
function Queue:retry(name, id)
    if not self.driver then return 0 end
    return self.driver:retry(name or self.settings.queue, id, now())
end

function Queue:clear_failed(name)
    if not self.driver then return 0 end
    return self.driver:clear_failed(name or self.settings.queue)
end

return Queue
