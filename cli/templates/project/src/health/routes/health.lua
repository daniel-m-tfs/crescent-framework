local action = require("src.health.actions.health")

return function(app, prefix)
    app:get(prefix, action.show)
end
