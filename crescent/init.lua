-- crescent/init.lua
-- Ponto de entrada principal do framework Crescent

local Server = require("crescent.server")

-- Middlewares
local cors = require("crescent.middleware.cors")
local security = require("crescent.middleware.security")
local auth = require("crescent.middleware.auth")
local logger = require("crescent.middleware.logger")
local static = require("crescent.middleware.static")

-- Core
local response = require("crescent.core.response")
local request = require("crescent.core.request")

-- Utils
local string_utils = require("crescent.utils.string")
local path_utils = require("crescent.utils.path")
local headers_utils = require("crescent.utils.headers")

-- API pública do framework
local Crescent = {
    -- Versão do framework (mantida em sincronia com package.lua)
    VERSION = "1.0.2",

    -- Cria nova aplicação
    new = Server.new,

    -- Middlewares
    middleware = {
        cors = cors,
        security = security,
        auth = auth,
        logger = logger,
        static = static
    },
    
    -- Core utilities
    response = response,
    request = request,
    
    -- Utilities
    utils = {
        string = string_utils,
        path = path_utils,
        headers = headers_utils
    }
}

-- Metatable para facilitar uso direto
setmetatable(Crescent, {
    __call = function(_, ...)
        return Server.new(...)
    end
})

return Crescent
