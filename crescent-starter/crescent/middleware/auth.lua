-- crescent/middleware/auth.lua
-- Middlewares de autenticação

local M = {}

-- Middleware de autenticação Bearer Token simples
function M.bearer(validator)
    if type(validator) ~= "function" then
        error("validator must be a function")
    end
    
    return function(ctx, next)
        local token = ctx.getBearer()
        
        if not token then
            ctx.error(401, "missing or invalid authorization header")
            return false
        end
        
        -- Valida token usando função fornecida
        local ok, user_or_error = validator(token, ctx)
        
        if not ok then
            ctx.error(401, user_or_error or "unauthorized")
            return false
        end
        
        -- Armazena dados do usuário no context state
        ctx.state.user = user_or_error
        
        if next then
            return next()
        end
        return true
    end
end

-- Middleware de Basic Auth
function M.basic(validator)
    if type(validator) ~= "function" then
        error("validator must be a function")
    end
    
    return function(ctx, next)
        local auth = ctx.getHeader("authorization")
        
        if not auth then
            ctx.res:setHeader("WWW-Authenticate", 'Basic realm="Access"')
            ctx.error(401, "missing authorization header")
            return false
        end
        
        local scheme, credentials = auth:match("^(%S+)%s+(.+)$")
        
        if not scheme or scheme:lower() ~= "basic" then
            ctx.error(401, "invalid authorization scheme")
            return false
        end
        
        -- Decodifica Base64 (implementação simplificada)
        -- Em produção, use biblioteca adequada
        local decoded = credentials -- TODO: implementar decode base64
        local username, password = decoded:match("^([^:]+):(.+)$")
        
        if not username or not password then
            ctx.error(401, "invalid credentials format")
            return false
        end
        
        -- Valida credenciais
        local ok, user_or_error = validator(username, password, ctx)
        
        if not ok then
            ctx.res:setHeader("WWW-Authenticate", 'Basic realm="Access"')
            ctx.error(401, user_or_error or "invalid credentials")
            return false
        end
        
        ctx.state.user = user_or_error
        
        if next then
            return next()
        end
        return true
    end
end

-- Middleware de API Key (header customizado)
function M.api_key(header_name, validator)
    header_name = header_name or "x-api-key"
    
    if type(validator) ~= "function" then
        error("validator must be a function")
    end
    
    return function(ctx, next)
        local key = ctx.getHeader(header_name)
        
        if not key or key == "" then
            ctx.error(401, "missing api key")
            return false
        end
        
        -- Valida chave
        local ok, user_or_error = validator(key, ctx)
        
        if not ok then
            ctx.error(401, user_or_error or "invalid api key")
            return false
        end
        
        ctx.state.user = user_or_error
        
        if next then
            return next()
        end
        return true
    end
end

return M
