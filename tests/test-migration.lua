package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local MigrationRunner = require("crescent.database.migration")

local function migration_tests()
    local statements = {}
    local adapter = {
        execute = function(self, sql, bindings)
            statements[#statements + 1] = { sql = sql, bindings = bindings }
            return true
        end,
    }
    local applied = {}
    local runner = MigrationRunner.new(adapter, applied)
    local migrations = {
        { name = "2026_02_add_posts", up = function() return { sql = "CREATE TABLE posts", bindings = {} } end, down = function() return "DROP TABLE posts" end },
        { name = "2026_01_create_users", up = function() return "CREATE TABLE users" end, down = function() return "DROP TABLE users" end },
    }
    local migrated = runner:migrate(migrations)
    tests.assertTableEquals(migrated, { "2026_01_create_users", "2026_02_add_posts" })
    tests.assertEquals(statements[1].sql, "CREATE TABLE users")
    tests.assertEquals(statements[2].sql, "CREATE TABLE posts")
    tests.assertTableEquals(runner:migrate(migrations), {})

    local rolled_back = runner:rollback(migrations)
    tests.assertTableEquals(rolled_back, { "2026_02_add_posts" })
    tests.assertEquals(statements[3].sql, "DROP TABLE posts")

    local failed_runner = MigrationRunner.new({ execute = function() return nil, "ddl failed" end }, {})
    local result, name, error_message = failed_runner:migrate({
        { name = "bad", up = function() return "CREATE bad" end, down = function() return "DROP bad" end },
    })
    tests.assertNil(result)
    tests.assertEquals(name, "bad")
    tests.assertEquals(error_message, "ddl failed")
end

assert(tests.runSuite("Migrations", { ordering_and_rollback = migration_tests }))