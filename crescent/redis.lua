-- Redis client on lua-resty-redis (bundled with OpenResty, non-blocking
-- cosockets). Used by the "redis" drivers of crescent.cache and
-- crescent.queue; apps can use it directly too:
--
--   local redis = Redis.new(config.redis)
--   redis:command("set", "key", "value")
--   redis:with(function(red) red:init_pipeline() ... return red:commit_pipeline() end)
--
-- Like the MySQL adapter, the client holds no connection: every call borrows
-- one from the nginx cosocket pool and gives it back with set_keepalive().
-- The pool name includes host, port and database, so connections that ran
-- SELECT are never mixed with connections of another database.
local Redis = {}
Redis.__index = Redis

local DEFAULTS = {
    host = "127.0.0.1",
    port = 6379,
    database = 0,
    connect_timeout = 1000,
    send_timeout = 5000,
    read_timeout = 5000,
    max_idle_timeout = 10000,
    pool_size = 100,
}

local function default_factory()
    return require("resty.redis")
end

local function null_to_nil(value)
    if ngx and value == ngx.null then return nil end
    if type(value) == "table" then
        for index = 1, #value do
            if ngx and value[index] == ngx.null then value[index] = nil end
        end
    end
    return value
end

Redis.null_to_nil = null_to_nil

-- config: host, port, password, username (Redis 6 ACL), database,
-- ssl, ssl_verify, server_name, timeouts (ms), pool_size.
-- driver injects a fake `resty.redis` module or factory, mostly for tests.
function Redis.new(config, driver)
    config = config or {}
    if type(config) ~= "table" then error("redis config must be a table", 2) end
    local settings = {}
    for key, value in pairs(DEFAULTS) do settings[key] = value end
    for key, value in pairs(config) do settings[key] = value end
    if settings.password == "" then settings.password = nil end
    if settings.username == "" then settings.username = nil end
    if not settings.path and (type(settings.host) ~= "string" or settings.host == "") then
        error("redis config requires host", 2)
    end
    settings.database = tonumber(settings.database) or 0
    settings.pool_name = settings.pool_name or string.format("crescent:redis:%s:%s:%d",
        settings.path or settings.host, tostring(settings.port), settings.database)

    local factory = driver or default_factory
    if type(factory) == "table" then
        local module = factory
        factory = function() return module end
    end
    if type(factory) ~= "function" then error("redis driver must be a module or factory function", 2) end
    return setmetatable({ config = settings, factory = factory }, Redis)
end

function Redis:connect()
    local config = self.config
    local red, err = self.factory():new()
    if not red then return nil, "redis: unable to create connection: " .. tostring(err) end
    red:set_timeouts(config.connect_timeout, config.send_timeout, config.read_timeout)

    local ok, connect_err
    local options = { pool = config.pool_name, ssl = config.ssl, ssl_verify = config.ssl_verify, server_name = config.server_name }
    if config.path then
        ok, connect_err = red:connect(config.path, options)
    else
        ok, connect_err = red:connect(config.host, config.port, options)
    end
    if not ok then return nil, "redis: connect failed: " .. tostring(connect_err) end

    -- AUTH and SELECT only on new connections; pooled ones already ran them.
    local reused = red.get_reused_times and red:get_reused_times() or 0
    if reused == 0 then
        if config.password then
            local authed, auth_err
            if config.username then
                authed, auth_err = red:auth(config.username, config.password)
            else
                authed, auth_err = red:auth(config.password)
            end
            if not authed then
                red:close()
                return nil, "redis: auth failed: " .. tostring(auth_err)
            end
        end
        if config.database ~= 0 then
            local selected, select_err = red:select(config.database)
            if not selected then
                red:close()
                return nil, "redis: select failed: " .. tostring(select_err)
            end
        end
    end
    return red
end

-- Runs fn(red) on a pooled connection and returns its results. An error
-- raised by fn closes the connection (it may hold an unread reply) and is
-- re-raised; lua-resty-redis itself closes the socket on timeouts, so the
-- set_keepalive() that follows a failed command is harmless.
function Redis:with(fn)
    local red, err = self:connect()
    if not red then return nil, err end
    local results = { pcall(fn, red) }
    if not results[1] then
        red:close()
        error(results[2], 0)
    end
    red:set_keepalive(self.config.max_idle_timeout, self.config.pool_size)
    return unpack(results, 2, table.maxn(results))
end

-- One command: redis:command("hset", "key", "field", "value").
-- Redis nil replies come back as Lua nil (not ngx.null).
function Redis:command(name, ...)
    local args = { ... }
    local count = select("#", ...)
    return self:with(function(red)
        local result, err = red[name](red, unpack(args, 1, count))
        if result == nil then return nil, "redis: " .. tostring(err) end
        return null_to_nil(result)
    end)
end

-- EVAL with explicit keys and arguments.
function Redis:eval(script, keys, args)
    local params = { script, #keys }
    for _, key in ipairs(keys) do params[#params + 1] = key end
    for _, value in ipairs(args or {}) do params[#params + 1] = value end
    return self:command("eval", unpack(params))
end

function Redis:ping()
    local result, err = self:command("ping")
    if result ~= "PONG" then return nil, err or ("redis: unexpected PING reply " .. tostring(result)) end
    return true
end

return Redis
