-- example.lua
-- Exemplo de uso do framework Crescent

local crescent = require("crescent")

-- Carrega configuração baseada no ambiente
local env = os.getenv("ENV") or "development"
local config = require("config." .. env)

-- Cria aplicação
local app = crescent.new()

-- Configura servidor
app:set("max_body_size", config.server.max_body_size)

-- ============ MIDDLEWARES GLOBAIS ============

-- Logger
if config.logging.enabled then
    if config.logging.level == "detailed" then
        app:use(crescent.middleware.logger.detailed())
    else
        app:use(crescent.middleware.logger.basic())
    end
end

-- CORS
if config.cors.enabled then
    if config.cors.strict then
        app:use(crescent.middleware.cors.strict(config.cors.allowed_origins))
    else
        app:use(crescent.middleware.cors.default())
    end
end

-- Headers de segurança
if config.security.headers then
    app:use(crescent.middleware.security.headers())
end

-- Rate limiting
if config.security.rate_limit then
    app:use(crescent.middleware.security.rate_limit({
        window = config.security.rate_limit_window,
        max_requests = config.security.rate_limit_max
    }))
end

-- Proteção contra path traversal
if config.security.path_traversal then
    app:use(crescent.middleware.security.path_traversal())
end

-- ============ ROTAS PÚBLICAS ============

-- Health check
app:get("/health", function(ctx)
    return ctx.json(200, {
        status = "ok",
        timestamp = os.time(),
        environment = env
    })
end)

-- Rota raiz
app:get("/", function(ctx)
    return ctx.json(200, {
        message = "🌙 Welcome to Crescent Framework",
        version = crescent.VERSION,
        environment = env
    })
end)

-- Exemplo: GET com parâmetros de rota
app:get("/user/{id}", function(ctx)
    local user_id = ctx.params.id
    
    if not user_id then
        return ctx.error(400, "user id is required")
    end
    
    return ctx.json(200, {
        id = user_id,
        name = "John Doe",
        email = "john@example.com"
    })
end)

-- Exemplo: POST com body JSON
app:post("/user", function(ctx)
    if not ctx.body then
        return ctx.error(400, "invalid or missing json body")
    end
    
    local name = ctx.body.name
    local email = ctx.body.email
    
    if not name or not email then
        return ctx.error(400, "name and email are required")
    end
    
    return ctx.json(201, {
        id = 123,
        name = name,
        email = email,
        created_at = os.time()
    })
end)

-- ============ ROTAS COM AUTENTICAÇÃO ============

-- Middleware de autenticação para rotas protegidas
local auth_middleware = crescent.middleware.auth.bearer(function(token, ctx)
    -- Validação simples (em produção, validar JWT ou consultar DB)
    if token == "secret-token-123" then
        return true, {
            id = 1,
            username = "admin",
            role = "admin"
        }
    end
    return false, "invalid token"
end)

-- Grupo de rotas protegidas com prefixo /api
app:group("/api", function(app)
    -- Adiciona auth apenas para este grupo (exemplo - requer implementação)
    -- Em uma versão mais avançada, você poderia ter app:use_local()
    
    app:get("/profile", function(ctx)
        -- Em produção, ctx.state.user estaria disponível após auth
        local token = ctx.getBearer()
        
        if token ~= "secret-token-123" then
            return ctx.error(401, "unauthorized")
        end
        
        return ctx.json(200, {
            id = 1,
            username = "admin",
            role = "admin"
        })
    end)
    
    app:post("/data", function(ctx)
        local token = ctx.getBearer()
        
        if token ~= "secret-token-123" then
            return ctx.error(401, "unauthorized")
        end
        
        return ctx.json(200, {
            message = "data created",
            data = ctx.body
        })
    end)
end)

-- ============ ROTAS ADMINISTRATIVAS ============

app:group("/admin", function(app)
    app:get("/stats", function(ctx)
        -- Verificação de auth aqui
        return ctx.json(200, {
            requests_total = 1000,
            users_active = 50,
            uptime = 3600
        })
    end)
end)

-- ============ HANDLERS CUSTOMIZADOS ============

-- Handler 404
app:on_not_found(function(ctx)
    return ctx.json(404, {
        error = "endpoint not found",
        method = ctx.method,
        path = ctx.path,
        suggestion = "check the API documentation"
    })
end)

-- Handler de erro global
app:on_error(function(ctx, error)
    print("ERROR:", error)
    
    -- Em produção, não expor detalhes do erro
    if env == "production" then
        return ctx.json(500, {
            error = "internal server error",
            request_id = os.time() -- Log ID para rastreamento
        })
    else
        return ctx.json(500, {
            error = "internal server error",
            detail = tostring(error)
        })
    end
end)

-- ============ INICIA SERVIDOR ============

app:listen(config.server.port, config.server.host)

-- Mantém o processo rodando
require('luvit').run()
