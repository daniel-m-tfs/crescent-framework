-- main.lua
-- Exemplo de aplicação usando o Crescent Framework

local crescent = require("crescent")

-- Carrega configuração
local env = os.getenv("ENV") or "development"
local config = require("config." .. env)

print("🌙 Starting Crescent Application")
print("Environment: " .. env)
print()

-- Cria aplicação
local app = crescent.new()

-- Configura
app:set("max_body_size", config.server.max_body_size)

-- ============ MIDDLEWARES ============

-- Logger
app:use(crescent.middleware.logger.basic())

-- CORS
if config.cors.strict then
    app:use(crescent.middleware.cors.strict(config.cors.allowed_origins))
else
    app:use(crescent.middleware.cors.default())
end

-- Security
if config.security.headers then
    app:use(crescent.middleware.security.headers())
end

if config.security.rate_limit then
    app:use(crescent.middleware.security.rate_limit({
        window = config.security.rate_limit_window,
        max_requests = config.security.rate_limit_max
    }))
end

-- ============ ROTAS ============

-- Health check
app:get("/health", function(ctx)
    return ctx.json(200, {
        status = "ok",
        timestamp = os.time()
    })
end)

-- Root
app:get("/", function(ctx)
    return ctx.json(200, {
        message = "Welcome to Crescent API",
        version = crescent.VERSION,
        environment = env
    })
end)

-- Debug headers
app:get("/debug/headers", function(ctx)
    return { headers = ctx.headers, bearer = ctx.getBearer() }
end)

-- Users
app:get("/user/{id}", function(ctx)
    local names = { ["1"]="Daniel", ["2"]="Sarah", ["3"]="Miguel" }
    
    if ctx.params.id == nil then
        return ctx.json(200, { data = names })
    end
    
    local name = names[ctx.params.id]
    if not name then
        return ctx.json(404, { error = "user not found", id = ctx.params.id })
    end
    return { id = tonumber(ctx.params.id), name = name }
end)

-- Create user
app:post("/user", function(ctx)
    if not ctx.body or not ctx.body.name or ctx.body.name == "" then
        return ctx.json(422, { error="name is required" })
    end
    -- Simula criação
    return ctx.json(201, { id=99, name=ctx.body.name })
end)

-- Grupo de exemplo
app:group("/grupo", function(app)
    app:get("/us", function(ctx)
        return ctx.json(200, {data="funciona"})
    end)
end)

-- ============ ERROR HANDLERS ============

app:on_not_found(function(ctx)
    return ctx.json(404, {
        error = "not found",
        path = ctx.path
    })
end)

app:on_error(function(ctx, error)
    print("ERROR:", error)
    return ctx.json(500, {
        error = "internal server error"
    })
end)

-- ============ INICIA SERVIDOR ============

app:listen(config.server.port, config.server.host)

print("💡 Try:")
print("   curl http://" .. config.server.host .. ":" .. config.server.port .. "/health")
print("   curl http://" .. config.server.host .. ":" .. config.server.port .. "/user/1")
print()

require('luvit').run()

