package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local PgmoonAdapter = require("crescent.database.pgmoon")

local function adapter_tests()
    local calls = {}
    local fake = { connected = false }
    function fake:connect() self.connected = true; calls[#calls + 1] = "connect"; return true end
    function fake:disconnect() calls[#calls + 1] = "disconnect"; return true end
    function fake:query(sql, ...)
        calls[#calls + 1] = sql
        if sql == "SELECT 1" then tests.assertEquals(select("#", ...), 1) end
        if sql == "FAIL" then return nil, "query failed" end
        return true
    end

    local adapter = PgmoonAdapter.new({ database = "test" }, function() return fake end)
    tests.assertEquals(adapter:query("SELECT 1", { 7 }), true)
    tests.assertEquals(adapter:execute("UPDATE users SET name = ?", { "Ada" }), true)
    tests.assertEquals(adapter:transaction({
        { sql = "INSERT INTO users (id) VALUES (?)", bindings = { 1 } },
        { sql = "UPDATE users SET active = ?", bindings = { true } },
    }), true)
    tests.assertEquals(adapter:close(), true)
    tests.assertTableEquals(calls, {
        "connect", "SELECT 1", "UPDATE users SET name = ?", "BEGIN",
        "INSERT INTO users (id) VALUES (?)", "UPDATE users SET active = ?", "COMMIT", "disconnect",
    })

    local failed = PgmoonAdapter.new({}, function() return fake end)
    tests.assertNil(failed:transaction({ { sql = "FAIL" } }))
    tests.assertEquals(calls[#calls], "ROLLBACK")
end

assert(tests.runSuite("Pgmoon adapter", { contract = adapter_tests }))