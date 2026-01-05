-- src/hello/init.lua
-- Módulo Hello - Agrupa controllers, services e rotas

local Module = {}

function Module.register(app)
    -- Registra rotas do módulo
    local routes = require("src.hello.routes.hello")
    routes(app, "/hello")
    
    print("✓ Módulo Hello carregado")
end

return Module
