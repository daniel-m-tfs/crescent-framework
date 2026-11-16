-- Fixed-window rate limiting shared by all nginx workers (resty.limit.count
-- on an ngx.shared dict).
--
--   rate_limit.create({
--       limit = 100,               -- requests per window
--       window = 60,               -- seconds
--       dict = "crescent_limits",  -- lua_shared_dict name
--       prefix = "rl:",            -- key namespace, use one per limiter
--       key = function(ctx) return ctx.remote_addr end,  -- nil skips limiting
--   })
--
-- The default key is `ctx.remote_addr` (nginx $remote_addr). Behind a proxy,
-- make nginx resolve the real client address with the realip module
-- (set_real_ip_from + real_ip_header); never key on a raw X-Forwarded-For
-- header, which any client can forge to get a fresh bucket per request.
local RateLimit = {}

local function default_key(ctx)
    return ctx.remote_addr or "unknown"
end

local function log_error(message)
    if ngx and ngx.log then ngx.log(ngx.ERR, message) end
end

function RateLimit.create(options)
    options = options or {}
    local limit = options.limit or 100
    local window = options.window or 60
    local dict_name = options.dict or "crescent_limits"
    local prefix = options.prefix or "rl:"
    local key_fn = options.key or default_key
    assert(type(limit) == "number" and limit >= 1 and limit % 1 == 0, "rate_limit: limit must be a positive integer")
    assert(type(window) == "number" and window >= 1, "rate_limit: window must be at least 1 second")
    assert(type(key_fn) == "function", "rate_limit: key must be a function")

    local dict = ngx and ngx.shared and ngx.shared[dict_name]
    if not dict then
        error("rate_limit: shared dict '" .. dict_name .. "' not found; declare `lua_shared_dict "
            .. dict_name .. " 10m;` in nginx.conf", 2)
    end
    local limiter, err = require("resty.limit.count").new(dict_name, limit, window)
    if not limiter then error("rate_limit: " .. tostring(err), 2) end
    local limit_value = tostring(limit)

    return function(ctx, next)
        local key = key_fn(ctx)
        if key == nil then return next() end
        key = prefix .. tostring(key)

        local delay, remaining = limiter:incoming(key, true)
        local ttl = dict:ttl(key)
        local reset_in = math.max(1, math.ceil(tonumber(ttl) or window))
        if not delay then
            if remaining ~= "rejected" then
                -- Storage failure (e.g. dict out of memory): fail open.
                log_error("rate_limit: " .. tostring(remaining))
                return next()
            end
            ctx:header("Retry-After", tostring(reset_in))
            ctx:header("X-RateLimit-Limit", limit_value)
            ctx:header("X-RateLimit-Remaining", "0")
            ctx:header("X-RateLimit-Reset", tostring(ngx.time() + reset_in))
            return ctx:error(429, "too many requests", nil, "rate_limited")
        end
        ctx:header("X-RateLimit-Limit", limit_value)
        ctx:header("X-RateLimit-Remaining", tostring(remaining))
        ctx:header("X-RateLimit-Reset", tostring(ngx.time() + reset_in))
        return next()
    end
end

return RateLimit
