-- crescent/middleware/security.lua
-- Middlewares de segurança

local response = require("crescent.core.response")
local string_utils = require("crescent.utils.string")
local path_utils = require("crescent.utils.path")

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
    local sweep_every = options.sweep_every or 1000 -- requisições entre sweeps
    -- Por padrão NÃO confia em X-Forwarded-For/X-Real-IP: qualquer cliente
    -- direto (sem proxy de verdade na frente) pode setar esses headers à
    -- vontade e trocar de "IP" a cada request, resetando o próprio bucket
    -- de rate limit — bypass trivial. Só olha esses headers se o app
    -- explicitamente confirmar que roda atrás de um proxy confiável que os
    -- popula de forma segura (nginx, load balancer, etc.).
    local trust_proxy = options.trust_proxy or false
    local requests = {} -- {ip: {count, reset_time}}
    local requests_seen = 0

    -- Remove entradas cuja janela já expirou (evita memory leak sob tráfego
    -- de IPs que nunca mais voltam, ex.: scanners/bots)
    local function sweep(now)
        for ip, record in pairs(requests) do
            if now > record.reset then
                requests[ip] = nil
            end
        end
    end

    return function(ctx, next)
        -- Obtém IP. Só olha X-Forwarded-For/X-Real-IP quando trust_proxy
        -- está explicitamente ligado (ver comentário acima).
        local ip
        if trust_proxy then
            ip = ctx.getHeader("x-forwarded-for") or
                 ctx.getHeader("x-real-ip") or
                 ctx.req.socket.remoteAddress or
                 "unknown"
        else
            ip = ctx.req.socket.remoteAddress or "unknown"
        end

        local now = os.time()

        requests_seen = requests_seen + 1
        if requests_seen >= sweep_every then
            requests_seen = 0
            sweep(now)
        end

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

-- Proteção contra path traversal. Reusa path_utils.is_safe() (mesma fonte
-- usada por static.lua) em vez de uma checagem duplicada e incompleta que
-- só olhava "..", sem checar bytes nulos.
function M.path_traversal()
    return function(ctx, next)
        if not path_utils.is_safe(ctx.path) then
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
