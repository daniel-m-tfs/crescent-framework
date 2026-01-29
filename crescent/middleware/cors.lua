-- crescent/middleware/cors.lua
-- Middleware para configuração de CORS

local response = require("crescent.core.response")

local M = {}

-- Cria middleware CORS com opções configuráveis
function M.create(options)
    options = options or {}
    
    return function(ctx, next)
        -- Define headers CORS
        response.set_cors_headers(ctx.res, options)
        
        -- Responde imediatamente a requisições OPTIONS (preflight)
        if ctx.method == "OPTIONS" then
            ctx.no_content()
            return true
        end
        
        -- Continua para próximo middleware/handler
        if next then
            return next()
        end
        return true
    end
end

-- Middleware CORS padrão (permissivo para desenvolvimento)
function M.default()
    return M.create({
        origin = "*",
        methods = "GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD",
        headers = "Content-Type, Authorization",
        credentials = false
    })
end

-- Middleware CORS estrito (para produção)
function M.strict(allowed_origins)
    return function(ctx, next)
        local origin = ctx.getHeader("origin")
        
        -- Valida origin
        local allowed = false
        if type(allowed_origins) == "table" then
            for _, allowed_origin in ipairs(allowed_origins) do
                if origin == allowed_origin then
                    allowed = true
                    break
                end
            end
        elseif type(allowed_origins) == "string" then
            allowed = (origin == allowed_origins)
        end
        
        if allowed then
            response.set_cors_headers(ctx.res, {
                origin = origin,
                methods = "GET,POST,PUT,PATCH,DELETE,OPTIONS",
                headers = "Content-Type, Authorization",
                credentials = true,
                max_age = 86400
            })
        end
        
        -- Responde a preflight
        if ctx.method == "OPTIONS" then
            if allowed then
                ctx.no_content()
            else
                ctx.error(403, "origin not allowed")
            end
            return true
        end
        
        -- Bloqueia se origin não permitida e não é OPTIONS
        if not allowed and origin then
            ctx.error(403, "origin not allowed")
            return false
        end
        
        if next then
            return next()
        end
        return true
    end
end

return M
