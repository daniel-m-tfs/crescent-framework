-- app.lua
-- Aplicação principal do Crescent Framework
-- Estrutura modular inspirada no NestJS

-- Pré-carrega módulos do Luvit
require("./bootstrap")
local crescent = require("crescent")


-- Carrega configuração
local env = os.getenv("ENV") or "development"
local config = require("config." .. env)

print("🌙 Starting Crescent Application")
print("Environment: " .. env)
print("Version: " .. crescent.VERSION)
print()

-- Cria aplicação
local app = crescent.new()

-- Configurações
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

-- Security Headers
if config.security.headers then
    app:use(crescent.middleware.security.headers())
end

-- Rate Limiting
if config.security.rate_limit then
    app:use(crescent.middleware.security.rate_limit({
        window = config.security.rate_limit_window,
        max_requests = config.security.rate_limit_max
    }))
end

-- ============ ROTAS ============

-- Root
app:get("/", function(ctx)
    return ctx.json(200, {
        message = "🌙 Welcome to Crescent Framework",
        version = crescent.VERSION,
        environment = env,
        modules = {
            "hello"
        }
    })
end)

-- Health check
app:get("/health", function(ctx)
    return ctx.json(200, {
        status = "ok",
        timestamp = os.time(),
        environment = env
    })
end)

-- ============ MÓDULOS ============

-- Registra módulo Hello (exemplo)
local helloModule = require("src.hello")
helloModule.register(app)

-- Adicione seus módulos aqui
-- local userModule = require("src.user")
-- userModule.register(app)

-- ============ INICIA SERVIDOR ============

print("\n🚀 Iniciando servidor...")
print("📍 Host: " .. config.server.host)
print("📍 Port: " .. config.server.port)
print("\n💡 Rotas disponíveis:")
print("   GET  / - Welcome")
print("   GET  /health - Health check")
print("   GET  /hello - Lista todos")
print("   GET  /hello/{id} - Busca por ID")
print("   POST /hello - Cria novo")
print("   PUT  /hello/{id} - Atualiza")
print("   DELETE /hello/{id} - Remove")
print()

app:listen(config.server.port, config.server.host)
