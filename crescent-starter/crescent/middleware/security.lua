-- crescent/middleware/security.lua
-- Middlewares de segurança

local response = require("crescent.core.response")
local string_utils = require("crescent.utils.string")

local M = {}

-- Adiciona headers de segurança padrão
function M.headers()
    return function(ctx, next)
        response.set_security_headers(ctx.res)
        
        if next then
            return next()
        end
        return true
    end
end

-- Rate limiting simples (em memória)
function M.rate_limit(options)
    options = options or {}
    local window = options.window or 60 -- segundos
    local max_requests = options.max_requests or 100
    local requests = {} -- {ip: {count, reset_time}}
    
    return function(ctx, next)
        -- Obtém IP (considera X-Forwarded-For se atrás de proxy)
        local ip = ctx.getHeader("x-forwarded-for") or 
                   ctx.getHeader("x-real-ip") or
                   ctx.req.socket.remoteAddress or
                   "unknown"
        
        local now = os.time()
        local record = requests[ip]
        
        if not record or now > record.reset then
            requests[ip] = {
                count = 1,
                reset = now + window
            }
        else
            record.count = record.count + 1
            
            if record.count > max_requests then
                ctx.res:setHeader("Retry-After", tostring(record.reset - now))
                ctx.error(429, "too many requests")
                return false
            end
        end
        
        -- Define headers informativos
        ctx.res:setHeader("X-RateLimit-Limit", tostring(max_requests))
        ctx.res:setHeader("X-RateLimit-Remaining", 
                         tostring(max_requests - requests[ip].count))
        ctx.res:setHeader("X-RateLimit-Reset", 
                         tostring(requests[ip].reset))
        
        if next then
            return next()
        end
        return true
    end
end

-- Validação de Content-Length (proteção contra body muito grande)
function M.body_size_limit(max_size)
    max_size = max_size or 10 * 1024 * 1024 -- 10MB
    
    return function(ctx, next)
        local cl = ctx.getHeader("content-length")
        
        if cl then
            local size = tonumber(cl)
            if size and size > max_size then
                ctx.error(413, "payload too large")
                return false
            end
        end
        
        if next then
            return next()
        end
        return true
    end
end

-- Proteção contra path traversal
function M.path_traversal()
    return function(ctx, next)
        if ctx.path:find("%.%.", 1, true) then
            ctx.error(400, "invalid path")
            return false
        end
        
        if next then
            return next()
        end
        return true
    end
end

-- Validação de método HTTP
function M.allowed_methods(methods)
    local allowed = {}
    for _, m in ipairs(methods or {}) do
        allowed[m] = true
    end
    
    return function(ctx, next)
        if not allowed[ctx.method] then
            ctx.res:setHeader("Allow", table.concat(methods, ", "))
            ctx.error(405, "method not allowed")
            return false
        end
        
        if next then
            return next()
        end
        return true
    end
end

return M
