local Crescent = require("crescent")
local Config = require("crescent.config")
local config = Config.load()

local app = Crescent.new(config)

require("src.health").register(app)

return app:run()
