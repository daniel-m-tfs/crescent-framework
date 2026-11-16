local Application = require("crescent.application")

-- Optional subsystems load lazily, so an app that never uses e.g. JWT does
-- not need its dependencies (resty.openssl) to boot.
local lazy = {
    json = "crescent.json",
    env = "crescent.env",
    config = "crescent.config",
    validation = "crescent.validation",
    view = "crescent.view",
    logger = "crescent.logger",
    health = "crescent.health",
    database = "crescent.database",
    model = "crescent.model",
    http_client = "crescent.http_client",
    mail = "crescent.mail",
}

local groups = {
    security = {
        jwt = "crescent.security.jwt",
        password = "crescent.security.password",
    },
    middleware = {
        auth = "crescent.middleware.auth",
        cors = "crescent.middleware.cors",
        security_headers = "crescent.middleware.security_headers",
        rate_limit = "crescent.middleware.rate_limit",
        request_log = "crescent.middleware.request_log",
    },
}

local function lazy_table(modules)
    return setmetatable({}, {
        __index = function(t, key)
            local name = modules[key]
            if not name then return nil end
            local value = require(name)
            rawset(t, key, value)
            return value
        end,
    })
end

local Crescent = lazy_table(lazy)
Crescent.VERSION = "2.0.0"
Crescent.new = function(config) return Application.new(config) end
for name, modules in pairs(groups) do Crescent[name] = lazy_table(modules) end

return Crescent
