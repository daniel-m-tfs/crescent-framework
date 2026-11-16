package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Config = require("crescent.config")

local function config_tests()
    local development = Config.load("development")
    tests.assertEquals(development.environment, "development")
    tests.assertTrue(development.debug)
    tests.assertEquals(development.server.port, 8080)

    local production = Config.load("production")
    tests.assertEquals(production.environment, "production")
    tests.assertFalse(production.debug)

    tests.assertError(function()
        Config.load("../development")
    end, "environment name is invalid")

    tests.assertError(function()
        Config.validate({
            environment = "test",
            debug = true,
            server = { host = "127.0.0.1", port = 70000, max_body_size = 1024 },
        })
    end, "server.port must be an integer")

    tests.assertError(function()
        Config.validate({ environment = "test", debug = true })
    end, "server must be a table")
end

assert(tests.runSuite("Configuration", { loading_and_validation = config_tests }))