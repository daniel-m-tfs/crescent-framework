package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Adapter = require("crescent.database.adapter")

local function adapter_tests()
    local calls = {}
    local driver = {}
    for _, method in ipairs({ "connect", "query", "execute", "transaction", "close" }) do
        driver[method] = function(self, value)
            tests.assertEquals(self, driver)
            calls[#calls + 1] = method
            return method .. ":" .. tostring(value or "ok")
        end
    end

    local adapter = Adapter.new(driver)
    tests.assertTrue(adapter:is_adapter())
    tests.assertEquals(adapter:connect("db"), "connect:db")
    tests.assertEquals(adapter:query("select"), "query:select")
    tests.assertEquals(adapter:execute("insert"), "execute:insert")
    tests.assertEquals(adapter:transaction("tx"), "transaction:tx")
    tests.assertEquals(adapter:close("db"), "close:db")
    tests.assertTableEquals(calls, { "connect", "query", "execute", "transaction", "close" })

    -- the MySQL adapter satisfies the contract
    local MySQL = require("crescent.database.mysql")
    local mysql = MySQL.new({ host = "127.0.0.1", database = "app", user = "app" }, { new = function() end })
    tests.assertTrue(Adapter.new(mysql):is_adapter())

    tests.assertError(function() Adapter.new({}) end, "must implement connect()")
    tests.assertError(function() Adapter.new({ connect = function() end }) end, "must implement query()")
end

assert(tests.runSuite("Database adapter", { contract = adapter_tests }))