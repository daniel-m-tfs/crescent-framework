package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local QueryBuilder = require("crescent.database.query_builder")
local Database = require("crescent.database")

local function recording_adapter(rows)
    local adapter = { calls = {} }
    function adapter:query(sql, bindings)
        self.calls[#self.calls + 1] = { method = "query", sql = sql, bindings = bindings }
        return rows or {}
    end
    function adapter:execute(sql, bindings)
        self.calls[#self.calls + 1] = { method = "execute", sql = sql, bindings = bindings }
        return { affected_rows = 1, insert_id = 9 }
    end
    return adapter
end

local function select_tests()
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
    tests.assertEquals((QueryBuilder.table("users"):where("a", "!=", nil):where_not_null("b"):to_sql()),
        "SELECT * FROM `users` WHERE `a` IS NOT NULL AND `b` IS NOT NULL")
    tests.assertEquals((QueryBuilder.table("users"):where("name", "=", "="):to_sql()),
        "SELECT * FROM `users` WHERE `name` = ?")

    local or_sql, or_bindings = QueryBuilder.table("users")
        :where("role", "admin")
        :orWhere("role", "editor")
        :or_where_null("role")
        :to_sql()
    tests.assertEquals(or_sql, "SELECT * FROM `users` WHERE `role` = ? OR `role` = ? OR `role` IS NULL")
    tests.assertTableEquals(or_bindings, { "admin", "editor" })

    local group_sql, group_bindings = QueryBuilder.table("users")
        :where("active", true)
        :where(function(q) q:where("age", ">", 18):or_where("verified", true) end)
        :to_sql()
    tests.assertEquals(group_sql, "SELECT * FROM `users` WHERE `active` = ? AND (`age` > ? OR `verified` = ?)")
    tests.assertTableEquals(group_bindings, { true, 18, true })

    local join_sql = QueryBuilder.table("posts")
        :select("posts.*", "users.name AS author")
        :join("users", "users.id", "posts.user_id")
        :leftJoin("categories", "categories.id", "=", "posts.category_id")
        :whereNotIn("posts.id", { 1 })
        :to_sql()
    tests.assertEquals(join_sql, "SELECT `posts`.*, `users`.`name` AS `author` FROM `posts` INNER JOIN `users` ON `users`.`id` = `posts`.`user_id` LEFT JOIN `categories` ON `categories`.`id` = `posts`.`category_id` WHERE `posts`.`id` NOT IN (?)")

    tests.assertEquals((QueryBuilder.table("users"):paginate(3, 25):to_sql()), "SELECT * FROM `users` LIMIT 25 OFFSET 50")
    tests.assertEquals((QueryBuilder.table("users"):take(5):skip(10):to_sql()), "SELECT * FROM `users` LIMIT 5 OFFSET 10")
    tests.assertContains((QueryBuilder.table("users"):whereIn("id", {}):to_sql()), "1 = 0")

    local raw_sql, raw_bindings = QueryBuilder.table("users"):where_raw("LOWER(email) = ?", { "a@b.c" }):to_sql()
    tests.assertEquals(raw_sql, "SELECT * FROM `users` WHERE (LOWER(email) = ?)")
    tests.assertTableEquals(raw_bindings, { "a@b.c" })

    local count_sql = QueryBuilder.table("users"):where("a", 1):order_by("id"):limit(3):to_count_sql()
    tests.assertEquals(count_sql, "SELECT COUNT(*) AS `aggregate` FROM `users` WHERE `a` = ?")
end

local function rejection_tests()
    tests.assertError(function() QueryBuilder.new():table("users; DROP TABLE users") end, "invalid SQL identifier")
    tests.assertError(function() QueryBuilder.new():table("users"):where("id", "=; DROP", 1) end, "invalid SQL operator")
    tests.assertError(function() QueryBuilder.table("users"):where("id) OR (1", 1) end, "invalid SQL identifier")
    tests.assertError(function() QueryBuilder.table("users"):order_by("id", "DESC; DROP") end, "ASC or DESC")
    tests.assertError(function() QueryBuilder.table("users"):select("COUNT(*)") end, "invalid SQL identifier")
    tests.assertError(function() QueryBuilder.table("users"):join("x", "a", "OR 1=1", "b") end, "invalid SQL operator")
    tests.assertError(function() QueryBuilder.table("users"):limit(-1) end, "non-negative integer")
    tests.assertError(function() QueryBuilder.table("users"):paginate(0) end, "positive integer")
    tests.assertError(function() QueryBuilder.table("users"):to_update({ name = "x" }) end, "requires at least one where")
    tests.assertError(function() QueryBuilder.table("users"):to_delete() end, "requires at least one where")
    tests.assertError(function() QueryBuilder.table("users"):to_insert({ ["bad col"] = 1 }) end, "invalid SQL identifier")
    tests.assertError(function() QueryBuilder.new():to_sql() end, "requires a table")
end

local function write_tests()
    local insert_sql, insert_bindings = QueryBuilder.table("users"):to_insert({ name = "Ada", age = 36 })
    tests.assertEquals(insert_sql, "INSERT INTO `users` (`age`, `name`) VALUES (?, ?)")
    tests.assertTableEquals(insert_bindings, { 36, "Ada" })

    local batch_sql, batch_bindings = QueryBuilder.table("users"):to_insert({ { name = "A" }, { name = "B", age = 2 } })
    tests.assertEquals(batch_sql, "INSERT INTO `users` (`age`, `name`) VALUES (NULL, ?), (?, ?)")
    tests.assertTableEquals(batch_bindings, { "A", 2, "B" })

    local update_sql, update_bindings = QueryBuilder.table("users")
        :where("id", 1):or_where("id", 2)
        :to_update({ name = "x", bio = QueryBuilder.NULL })
    tests.assertEquals(update_sql, "UPDATE `users` SET `bio` = ?, `name` = ? WHERE `id` = ? OR `id` = ?")
    tests.assertEquals(update_bindings[1], QueryBuilder.NULL)
    tests.assertEquals(update_bindings[4], 2)

    local delete_sql, delete_bindings = QueryBuilder.table("users"):where("id", 4):to_delete()
    tests.assertEquals(delete_sql, "DELETE FROM `users` WHERE `id` = ?")
    tests.assertTableEquals(delete_bindings, { 4 })
end

local function execution_tests()
    local adapter = recording_adapter({ { id = 1 } })
    local rows = QueryBuilder.new():table("users"):where("id", 1):fetch(adapter)
    tests.assertEquals(rows[1].id, 1)
    tests.assertEquals(adapter.calls[1].sql, "SELECT * FROM `users` WHERE `id` = ?")
    tests.assertTableEquals(adapter.calls[1].bindings, { 1 })

    local builder = QueryBuilder.table("users", adapter):where("a", 1):limit(5)
    tests.assertEquals(builder:first().id, 1)
    tests.assertContains(adapter.calls[2].sql, "LIMIT 1")
    -- first() does not mutate the builder
    tests.assertContains((builder:to_sql()), "LIMIT 5")

    local count_adapter = recording_adapter({ { aggregate = "12" } })
    tests.assertEquals(QueryBuilder.table("users"):using(count_adapter):count(), 12)
    tests.assertTrue(QueryBuilder.table("users"):using(count_adapter):exists())

    local result = QueryBuilder.table("users"):insert(adapter, { name = "x" })
    tests.assertEquals(result.insert_id, 9)
    tests.assertEquals(adapter.calls[3].method, "execute")
    QueryBuilder.table("users", adapter):where("id", 1):update({ name = "y" })
    tests.assertEquals(adapter.calls[4].sql, "UPDATE `users` SET `name` = ? WHERE `id` = ?")
    QueryBuilder.table("users"):where("id", 1):delete(adapter)
    tests.assertEquals(adapter.calls[5].sql, "DELETE FROM `users` WHERE `id` = ?")

    -- without an explicit adapter the default database is used
    Database.reset()
    tests.assertError(function() QueryBuilder.table("users"):get() end, "not configured")
    local default = recording_adapter({ { id = 3 } })
    Database.set_default(default)
    tests.assertEquals(QueryBuilder.table("users"):get()[1].id, 3)
    tests.assertEquals(QueryBuilder.raw("SELECT ? AS x", { 1 })[1].id, 3)
    tests.assertEquals(default.calls[2].sql, "SELECT ? AS x")
    Database.reset()

    -- errors are passed through untouched
    local failing = {
        query = function() return nil, "boom", 1146, "42S02", "query" end,
        execute = function() return nil, "dup", 1062, "23000", "unique_violation" end,
    }
    local none, err, errno = QueryBuilder.table("users"):get(failing)
    tests.assertNil(none)
    tests.assertEquals(err, "boom")
    tests.assertEquals(errno, 1146)
    local _, _, _, _, kind = QueryBuilder.table("users"):insert(failing, { a = 1 })
    tests.assertEquals(kind, "unique_violation")
end

local function page_tests()
    local adapter = { calls = {} }
    function adapter:query(sql, bindings)
        self.calls[#self.calls + 1] = { sql = sql, bindings = bindings }
        if sql:find("COUNT(*)", 1, true) then return { { aggregate = "23" } } end
        return { { id = 11 }, { id = 12 }, { id = 13 } }
    end
    function adapter:execute() end

    local query = QueryBuilder.table("users"):where("active", 1):order_by("id"):limit(5)
    local result = assert(query:page("3", "10", adapter))
    tests.assertEquals(#adapter.calls, 2)
    tests.assertNotContains(adapter.calls[1].sql, "LIMIT")
    tests.assertNotContains(adapter.calls[1].sql, "ORDER BY")
    tests.assertContains(adapter.calls[2].sql, "LIMIT 10 OFFSET 20")
    tests.assertEquals(#result.data, 3)
    tests.assertTableEquals(result.meta, { page = 3, per_page = 10, total = 23, last_page = 3, from = 21, to = 23 })
    tests.assertEquals(query.limit_value, 5, "page() must not change the builder")

    adapter.calls = {}
    local capped = assert(QueryBuilder.table("users"):page("x", 5000, adapter))
    tests.assertEquals(capped.meta.page, 1, "invalid page falls back to 1")
    tests.assertEquals(capped.meta.per_page, QueryBuilder.MAX_PER_PAGE)

    local empty_adapter = { query = function(_, sql)
        if sql:find("COUNT(*)", 1, true) then return { { aggregate = 0 } } end
        return {}
    end, execute = function() end }
    local empty = assert(QueryBuilder.table("users"):page(1, 10, empty_adapter))
    tests.assertTableEquals(empty.meta, { page = 1, per_page = 10, total = 0, last_page = 1 })
end

assert(tests.runSuite("Query builder", {
    page = page_tests,
    select_compilation = select_tests,
    rejections = rejection_tests,
    write_compilation = write_tests,
    execution = execution_tests,
}))
