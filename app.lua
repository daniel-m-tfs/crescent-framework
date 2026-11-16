-- Builds the application once per worker. nginx calls `require("app"):run()`
-- for each request; with `lua_code_cache on` this module is loaded only once.
local Crescent = require("crescent")
local Config = require("crescent.config")

local app = Crescent.new(Config.load())

require("src.health").register(app)

return app
