-- app.lua
-- Arquivo principal da aplicação Crescent

-- Bootstrap: carrega módulos do Luvit e configura paths
require("./bootstrap")

local Crescent = require("crescent")
local app = Crescent.new()

-- Middleware global
local cors = require("crescent.middleware.cors")
local logger = require("crescent.middleware.logger")
local security = require("crescent.middleware.security")

app:use(logger.basic())
app:use(cors.create())
app:use(security.headers())

-- Registra módulos da aplicação
local usersModule = require("src.users")
usersModule.register(app)

-- Rota de health check
app:get("/health", function(ctx)
    return ctx.json(200, {
        status = "ok",
        timestamp = os.time()
    })
end)

-- Inicia o servidor
app:listen(8080, "0.0.0.0")
