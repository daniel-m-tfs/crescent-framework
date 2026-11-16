-- Builds the application once per worker. nginx calls `require("app"):run()`
-- for each request; with `lua_code_cache on` this module is loaded only once.
local Crescent = require("crescent")
local Config = require("crescent.config")

local app = Crescent.new(Config.load())

app:use(Crescent.middleware.security_headers.create())
app:use(Crescent.middleware.request_log.create({
    skip = function(ctx) return ctx.path == "/health" or ctx.path == "/ready" end,
}))

require("src.health").register(app)
require("src.hello").register(app)

return app
