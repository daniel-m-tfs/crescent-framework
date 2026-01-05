-- src/users/init.lua
-- Módulo Users - Agrupa controllers, services e rotas

local Module = {}

function Module.register(app)
    -- Registra rotas do módulo
    local routes = require("src.users.routes.users")
    routes(app, "/users")
    
    print("✓ Módulo Users carregado")
end

return Module
