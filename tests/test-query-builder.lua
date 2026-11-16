package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local QueryBuilder = require("crescent.database.query_builder")

local function query_tests()
    local sql, bindings = QueryBuilder.new()
        :table("users")
        :select("id", "name")
        :where("active", true)
        :where("name", "LIKE", "%Ada%")
        :whereIn("role", { "admin", "editor" })
        :orderBy("created_at", "DESC")
        :limit(10)
        :offset(20)
        :to_sql()

    tests.assertEquals(sql, "SELECT `id`, `name` FROM `users` WHERE `active` = ? AND `name` LIKE ? AND `role` IN (?, ?) ORDER BY `created_at` DESC LIMIT 10 OFFSET 20")
    tests.assertTableEquals(bindings, { true, "%Ada%", "admin", "editor" })
    tests.assertNotContains(sql, "Ada")

    local null_sql, null_bindings = QueryBuilder.new():table("users"):where("deleted_at", nil):toSql()
    tests.assertEquals(null_sql, "SELECT * FROM `users` WHERE `deleted_at` IS NULL")
    tests.assertTableEquals(null_bindings, {})

    local empty_sql = QueryBuilder.new():table("users"):whereIn("id", {}):to_sql()
    tests.assertContains(empty_sql, "1 = 0")
    tests.assertError(function() QueryBuilder.new():table("users; DROP TABLE users") end, "invalid SQL identifier")
    tests.assertError(function() QueryBuilder.new():table("users"):where("id", "=; DROP", 1) end, "invalid SQL operator")

    local received_sql, received_bindings
    local fake_adapter = {
        query = function(self, received, received_values)
            received_sql, received_bindings = received, received_values
            return { { id = 1 } }, nil
        end,
        execute = function(self, received, received_values)
            return received, received_values
        end,
    }
    local rows = QueryBuilder.new():table("users"):where("id", 1):fetch(fake_adapter)
    tests.assertEquals(rows[1].id, 1)
    tests.assertContains(received_sql, "WHERE `id` = ?")
    tests.assertTableEquals(received_bindings, { 1 })
    local executed_sql, executed_bindings = QueryBuilder.new():table("users"):where("id", 1):execute(fake_adapter)
    tests.assertContains(executed_sql, "WHERE `id` = ?")
    tests.assertTableEquals(executed_bindings, { 1 })
end

assert(tests.runSuite("Query builder", { bindings_and_identifiers = query_tests }))