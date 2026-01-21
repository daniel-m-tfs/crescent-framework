-- crescent/middleware/auth.lua
-- Middlewares de autenticação

local jwt = require("crescent.utils.jwt")
local env = require("crescent.utils.env")

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

-- Middleware de autenticação JWT
-- Verifica token JWT no header Authorization: Bearer <token>
-- @param options table: opções de configuração
--   - secret: chave secreta (padrão: JWT_SECRET do .env)
--   - issuer: issuer esperado (opcional)
--   - audience: audience esperado (opcional)
--   - getUserFromPayload: função para transformar payload em user (opcional)
function M.jwt(options)
    options = options or {}
    
    local secret = options.secret or env.get("JWT_SECRET")
    if not secret or secret == "" then
        error("JWT secret is required. Set JWT_SECRET in .env or pass as option")
    end
    
    local verify_options = {
        issuer = options.issuer,
        audience = options.audience
    }
    
    return function(ctx, next)
        local token = ctx.getBearer()
        
        if not token then
            ctx.error(401, "missing or invalid authorization header")
            return false
        end
        
        -- Verifica e decodifica token
        local ok, payload_or_error = jwt.verify(token, secret, verify_options)
        
        if not ok then
            ctx.error(401, payload_or_error or "invalid token")
            return false
        end
        
        -- Permite customização de como extrair user do payload
        local user
        if options.getUserFromPayload and type(options.getUserFromPayload) == "function" then
            user = options.getUserFromPayload(payload_or_error, ctx)
        else
            user = payload_or_error
        end
        
        -- Armazena payload completo e user no context
        ctx.state.jwt_payload = payload_or_error
        ctx.state.user = user
        
        if next then
            return next()
        end
        return true
    end
end

-- Helper para gerar tokens JWT
-- @param payload table: dados a incluir no token
-- @param options table: opções (secret, expiresIn, issuer, audience)
-- @return string: token gerado
function M.generate_token(payload, options)
    options = options or {}
    local secret = options.secret or env.get("JWT_SECRET")
    
    if not secret or secret == "" then
        error("JWT secret is required")
    end
    
    return jwt.sign(payload, secret, options)
end

-- Helper para gerar Access Token com expiração padrão
-- @param payload table: dados a incluir no token
-- @param options table: opções (secret, expiresIn)
-- @return string: token gerado
function M.generate_access_token(payload, options)
    options = options or {}
    options.expiresIn = options.expiresIn or (15 * 60) -- 15 minutos
    return M.generate_token(payload, options)
end

-- Helper para gerar par de tokens (access + refresh)
-- @param user table|number: dados do usuário ou ID do usuário
-- @param options table: opções customizadas
-- @return table: { access_token, refresh_token, expires_in }
function M.generate_token_pair(user, options)
    options = options or {}
    local secret = options.secret or env.get("JWT_SECRET")
    
    if not secret or secret == "" then
        error("JWT secret is required")
    end
    
    local access_expires = options.access_expires_in or (15 * 60) -- 15 min
    local refresh_expires = options.refresh_expires_in or (30 * 24 * 60 * 60) -- 30 dias
    
    -- Prepara payload do JWT
    local payload = {
        user_id = user.id,
        name = user.name,
        email = user.email
    }
    
    local access_token = jwt.create_access_token(payload, secret, access_expires)
    local refresh_token = jwt.create_refresh_token(payload, secret, refresh_expires)
    
    return {
        access_token = access_token,
        refresh_token = refresh_token,
        token_type = "Bearer",
        expires_in = access_expires
    }
end

-- Helper para verificar token manualmente (fora do middleware)
-- @param token string: token a verificar
-- @param options table: opções de verificação
-- @return boolean, table/string: (sucesso, payload_ou_erro)
function M.verify_token(token, options)
    options = options or {}
    local secret = options.secret or env.get("JWT_SECRET")
    
    if not secret or secret == "" then
        error("JWT secret is required")
    end
    
    return jwt.verify(token, secret, options)
end

-- Helper para decodificar token sem verificar (apenas para debug)
-- @param token string: token a decodificar
-- @return table, table: header, payload
function M.decode_token(token)
    return jwt.decode(token)
end

return M
