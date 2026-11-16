-- Liveness and readiness endpoints.
--   GET /health -> 200 while the worker can serve requests (no dependencies)
--   GET /ready  -> 200 when every check passes, 503 otherwise
-- Load balancers and orchestrators should route traffic on /ready and
-- restart on /health.
local Health = {}

local function database_check(ctx)
    local db = ctx.db
    if not db then return nil, "database not configured" end
    local rows, err = db:query("SELECT 1 AS ok")
    if not rows then return nil, err end
    return true
end

Health.checks = { database = database_check }

local function now()
    if ngx and ngx.now then
        ngx.update_time()
        return ngx.now()
    end
    return os.time()
end

-- options: path (default "/health"), ready_path (default "/ready"),
-- checks = { name = function(ctx) -> true | nil, err } (default: database
-- when the app has one), service (name shown in the payload).
-- Check errors are logged but not exposed unless debug is on.
function Health.register(app, options)
    options = options or {}
    local checks = options.checks
    if checks == nil then checks = app.db and { database = database_check } or {} end
    local service = options.service or "crescent"

    app:get(options.path or "/health", function(ctx)
        return ctx:json(200, {
            status = "ok",
            service = service,
            environment = ctx.config.environment,
            timestamp = now(),
        })
    end, "health")

    app:get(options.ready_path or "/ready", function(ctx)
        local results, ready = {}, true
        for name, check in pairs(checks) do
            local started = now()
            local ok, passed, err = pcall(check, ctx)
            if not ok then passed, err = nil, passed end
            local entry = { status = passed and "ok" or "failing", duration_ms = math.floor((now() - started) * 1000 + 0.5) }
            if not passed then
                ready = false
                if ctx.debug then entry.error = tostring(err) end
                ctx.app.logger("warn", "readiness check failed: " .. name .. ": " .. tostring(err),
                    { request_id = ctx.request_id, check = name })
            end
            results[name] = entry
        end
        return ctx:json(ready and 200 or 503, { status = ready and "ready" or "not_ready", checks = results })
    end, "ready")
    return app
end

return Health
