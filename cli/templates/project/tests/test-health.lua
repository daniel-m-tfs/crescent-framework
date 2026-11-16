package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local json = require("crescent.json")

local function health_responds()
    local app = Crescent.new({ environment = "test", debug = true })
    require("src.health").register(app)
    local writer = { headers = {} }
    app:handle({ method = "GET", path = "/health", headers = {}, query = {} }, writer)
    tests.assertEquals(writer.status, 200)
    tests.assertEquals(json.decode(writer.body).status, "ok")
end

assert(tests.runSuite("Health", { health_responds = health_responds }))
