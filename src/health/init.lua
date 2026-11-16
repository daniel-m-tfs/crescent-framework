local Module = {}

function Module.register(app)
    local routes = require("src.health.routes.health")
    routes(app, "/health")
end

return Module
