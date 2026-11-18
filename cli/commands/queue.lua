-- queue:* and cache:clear. They load app.lua (OpenResty runtime, run through
-- bin/crescent) and use the queue/cache it configures.
--
--   queue:work [--queue=default,mail] [--sleep=1] [--once] [--max-jobs=N]
--              [--max-time=S] [--stop-when-empty]
--   queue:status [queue]             ready / delayed / reserved / failed
--   queue:failed [queue]             newest failed jobs
--   queue:retry [id|all] [--queue=]  requeue failed jobs
--   queue:clear-failed [queue]
--   cache:clear
local cli_output = require("crescent.utils.cli_output")

local QueueCommand = {}

-- --name=value / --flag -> options; everything else -> positional.
function QueueCommand.parse(args)
    local options, positional = {}, {}
    for _, value in ipairs(args or {}) do
        local key, option = value:match("^%-%-([%w%-]+)=(.*)$")
        if key then
            options[key] = option
        elseif value:match("^%-%-[%w%-]+$") then
            options[value:sub(3)] = true
        else
            positional[#positional + 1] = value
        end
    end
    return options, positional
end

local function load_app()
    local ok, app = pcall(require, "app")
    if not ok then
        cli_output.print_error("unable to load app.lua: " .. tostring(app))
        return nil
    end
    if type(app) ~= "table" or type(app.router) ~= "table" then
        cli_output.print_error("app.lua must return the application")
        return nil
    end
    return app
end

local SHARED_HINT = "the \"shared\" driver lives in the OpenResty server's memory, which the CLI cannot reach; "
    .. "set QUEUE_DRIVER=redis (and REDIS_*) in .env to use a separate worker and these commands"

local function load_queue(for_worker)
    local app = load_app()
    if not app then return nil end
    local queue = app.queue
    if not queue then
        cli_output.print_error("no queue configured: add a `queue` section to config/<env>.lua")
        return nil
    end
    local driver = queue.settings.driver
    if driver == "shared" then
        cli_output.print_error(SHARED_HINT)
        if for_worker then
            cli_output.print_info("With the shared driver, workers start inside OpenResty (config.queue.workers.embedded).")
        end
        return nil
    end
    if driver == "sync" then
        cli_output.print_error("the \"sync\" driver runs jobs inside push(); there is nothing to work on")
        return nil
    end
    return queue, app
end

local function number_option(options, name)
    local value = options[name]
    if value == nil then return nil end
    local number = tonumber(value)
    if not number or number < 0 then error("--" .. name .. " must be a number >= 0", 0) end
    return number
end

local function split(value)
    local items = {}
    for item in tostring(value):gmatch("[^,%s]+") do items[#items + 1] = item end
    return items
end

-- The resty CLI drops ngx.log below "warn", which would hide job logs, so
-- the default logger writes JSON lines to stdout instead (docker logs).
local function stdout_logger()
    local logger = require("crescent.logger").new({
        sink = function(_, line)
            io.stdout:write(line, "\n")
            io.stdout:flush()
        end,
    })
    return function(level, message, fields) logger:log(level, message, fields) end
end

function QueueCommand.work(args)
    local options = QueueCommand.parse(args)
    local queue, app = load_queue(true)
    if not queue then return false end
    if app.config.logger == nil then queue.logger = stdout_logger() end
    local ok, work_options = pcall(function()
        return {
            queues = options.queue and split(options.queue) or nil,
            sleep = number_option(options, "sleep"),
            max_jobs = options.once and 1 or number_option(options, "max-jobs"),
            max_time = number_option(options, "max-time"),
            stop_when_empty = options["stop-when-empty"] == true or options.once == true,
        }
    end)
    if not ok then
        cli_output.print_error(work_options)
        return false
    end
    local queues = work_options.queues or queue.settings.workers.queues
    cli_output.print_info(string.format("Worker started (driver %s, queues: %s). Ctrl+C to stop.",
        queue.settings.driver, table.concat(queues, ", ")))
    local processed = queue:work(work_options)
    cli_output.print_success(string.format("Worker stopped after %d job(s)", processed))
    return true
end

function QueueCommand.status(args)
    local _, positional = QueueCommand.parse(args)
    local queue = load_queue()
    if not queue then return false end
    local names = positional[1] and { positional[1] } or queue.settings.workers.queues
    print(string.format("%-20s %8s %8s %9s %7s", "QUEUE", "READY", "DELAYED", "RESERVED", "FAILED"))
    for _, name in ipairs(names) do
        local size, err = queue:size(name)
        if not size then
            cli_output.print_error(tostring(err))
            return false
        end
        print(string.format("%-20s %8d %8d %9d %7d", name, size.ready, size.delayed, size.reserved, size.failed))
    end
    return true
end

function QueueCommand.failed(args)
    local options, positional = QueueCommand.parse(args)
    local queue = load_queue()
    if not queue then return false end
    local name = positional[1] or options.queue or queue.settings.queue
    local entries, err = queue:failed(name, tonumber(options.limit) or 20)
    if not entries then
        cli_output.print_error(tostring(err))
        return false
    end
    if #entries == 0 then
        cli_output.print_success("No failed jobs in '" .. name .. "'")
        return true
    end
    for _, entry in ipairs(entries) do
        local when = os.date("!%Y-%m-%d %H:%M:%S", math.floor(tonumber(entry.failed_at) or 0))
        print(string.format("%s%s%s  %s  %s  (%s attempt(s), %s UTC)", cli_output.colors.bold, tostring(entry.id),
            cli_output.colors.reset, tostring(entry.name), name, tostring(entry.attempts), when))
        print("  " .. cli_output.colors.dim .. (tostring(entry.error):match("^[^\n]*") or "") .. cli_output.colors.reset)
    end
    cli_output.print_info("Requeue: lua cli.lua queue:retry <id|all> --queue=" .. name)
    return true
end

function QueueCommand.retry(args)
    local options, positional = QueueCommand.parse(args)
    local target = positional[1]
    if not target then
        cli_output.print_error("missing argument. Usage: lua cli.lua queue:retry <id|all> [--queue=name]")
        return false
    end
    local queue = load_queue()
    if not queue then return false end
    local name = options.queue or queue.settings.queue
    local count, err = queue:retry(name, target ~= "all" and target or nil)
    if not count then
        cli_output.print_error(tostring(err))
        return false
    end
    if count == 0 then
        cli_output.print_warning("No matching failed jobs in '" .. name .. "'")
    else
        cli_output.print_success(string.format("Requeued %d job(s) in '%s'", count, name))
    end
    return true
end

function QueueCommand.clear_failed(args)
    local options, positional = QueueCommand.parse(args)
    local queue = load_queue()
    if not queue then return false end
    local name = positional[1] or options.queue or queue.settings.queue
    local count, err = queue:clear_failed(name)
    if not count then
        cli_output.print_error(tostring(err))
        return false
    end
    cli_output.print_success(string.format("Deleted %d failed job(s) from '%s'", count, name))
    return true
end

function QueueCommand.cache_clear()
    local app = load_app()
    if not app then return false end
    if not app.cache then
        cli_output.print_error("no cache configured: add a `cache` section to config/<env>.lua")
        return false
    end
    if app.cache.settings.driver == "shared" then
        cli_output.print_error("the \"shared\" cache lives in the OpenResty server's memory; "
            .. "reload the server to clear it (lua cli.lua server reload, or lua cli.lua rerun with Docker)")
        return false
    end
    local ok, err = app.cache:flush()
    if not ok then
        cli_output.print_error(tostring(err))
        return false
    end
    cli_output.print_success("Cache cleared (keys under " .. app.cache.prefix .. ")")
    return true
end

return QueueCommand
