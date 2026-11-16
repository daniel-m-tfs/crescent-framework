-- Logs one structured entry per request (method, path, status, duration,
-- request id, client address, user id) and exposes a request-scoped logger as
-- `ctx.state.log` for actions. nginx's access_log stays the source of truth
-- for traffic; this adds application context to it.
local Logger = require("crescent.logger")

local RequestLog = {}

local function now()
    if ngx and ngx.now then
        ngx.update_time()
        return ngx.now()
    end
    return os.clock()
end

-- options: logger (crescent.logger instance), level (default "info"),
-- skip(ctx) -> true to skip (e.g. health checks), user_id(ctx) -> value.
function RequestLog.create(options)
    options = options or {}
    local logger = options.logger or Logger.new()
    local level = options.level or "info"
    local skip = options.skip
    local user_id = options.user_id or function(ctx)
        local user = ctx.state.user
        return type(user) == "table" and (user.id or user.user_id) or nil
    end

    return function(ctx, next)
        if skip and skip(ctx) then return next() end
        local request_logger = logger:with({ request_id = ctx.request_id })
        ctx.state.log = request_logger
        local started = now()
        local result = next()
        local status = ctx.res.writer.status or 200
        local entry_level = status >= 500 and "error" or (status >= 400 and "warn" or level)
        request_logger:log(entry_level, "request", {
            method = ctx.method,
            path = ctx.path,
            route = ctx.route,
            status = status,
            duration_ms = math.floor((now() - started) * 1000 + 0.5),
            remote_addr = ctx.remote_addr,
            user_id = user_id(ctx),
        })
        return result
    end
end

return RequestLog
