local Health = require("crescent.health")

local Module = {}

-- GET /health (liveness) and GET /ready (checks the database when configured).
function Module.register(app)
    Health.register(app, { service = "{{project}}" })
end

return Module
