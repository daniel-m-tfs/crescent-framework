package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Sql = require("crescent.database.sql")
local MySQL = require("crescent.database.mysql")
local Database = require("crescent.database")

local CONFIG = { host = "127.0.0.1", port = 3306, database = "app", user = "app", password = "x" }

-- Fake resty.mysql: on_query(sql) returns what the real driver would.
local function fake_driver(on_query)
    local log = { connects = 0, keepalives = 0, closes = 0, queries = {}, timeouts = {} }
    local module = {}
    function module.new()
        local conn = {}
        function conn:set_timeout(ms) log.timeouts[#log.timeouts + 1] = ms return true end
        function conn:connect(opts)
            log.connects = log.connects + 1
            log.opts = opts
            if log.connect_error then return nil, log.connect_error end
            return true
        end
        function conn:query(sql)
            log.queries[#log.queries + 1] = sql
            if on_query then return on_query(sql, log) end
            return { affected_rows = 0, insert_id = 0, server_status = 2 }
        end
        function conn:set_keepalive(idle, size)
            log.keepalives = log.keepalives + 1
            log.keepalive_args = { idle, size }
            return true
        end
        function conn:close() log.closes = log.closes + 1 return true end
        return conn
    end
    return module, log
end

local function binding_tests()
    tests.assertEquals(Sql.bind("SELECT 1"), "SELECT 1")
    tests.assertEquals(Sql.bind("SELECT * FROM t WHERE a = ? AND b = ?", { "x", 2 }),
        "SELECT * FROM t WHERE a = 'x' AND b = 2")
    -- `?` inside literals, identifiers and comments is not a placeholder
    tests.assertEquals(Sql.bind("SELECT '?', \"?\", `a?` FROM t WHERE c = ? -- why?\n AND d = ? /* ? */", { 1, 2 }),
        "SELECT '?', \"?\", `a?` FROM t WHERE c = 1 -- why?\n AND d = 2 /* ? */")
    tests.assertEquals(Sql.bind("SELECT 'it''s ?', 'a\\'?' WHERE x = ?", { 1 }),
        "SELECT 'it''s ?', 'a\\'?' WHERE x = 1")
    -- values containing ? and % are not re-processed
    tests.assertEquals(Sql.bind("INSERT INTO t VALUES (?, ?)", { "50% off?", "%1 %%" }),
        "INSERT INTO t VALUES ('50% off?', '%1 %%')")
    -- injection attempts stay inside a quoted literal
    local injected = Sql.bind("SELECT * FROM users WHERE name = ?", { "x' OR '1'='1" })
    tests.assertEquals(injected, "SELECT * FROM users WHERE name = 'x\\' OR \\'1\\'=\\'1'")
    tests.assertEquals(Sql.bind("SELECT ?", { "a\\'; DROP TABLE users; --" }),
        "SELECT 'a\\\\\\'; DROP TABLE users; --'")
    tests.assertEquals(Sql.bind("SELECT ?", { "nul\0byte\n" }), "SELECT 'nul\\0byte\\n'")
    -- types
    tests.assertEquals(Sql.bind("VALUES (?, ?, ?, ?, ?)", { n = 5, true, false, nil, Sql.NULL, 1.5 }),
        "VALUES (1, 0, NULL, NULL, 1.5)")
    tests.assertEquals(Sql.bind("VALUES (?, ?)", { 2 ^ 53 - 1, -42 }), "VALUES (9007199254740991, -42)")
    tests.assertEquals(Sql.bind("VALUES (?, ?, ?)", { 1, nil, 3 }), "VALUES (1, NULL, 3)")
    -- rejections
    local sql, err = Sql.bind("SELECT ?", { 0 / 0 })
    tests.assertNil(sql)
    tests.assertContains(err, "NaN")
    sql, err = Sql.bind("SELECT ?", { math.huge })
    tests.assertNil(sql)
    sql, err = Sql.bind("SELECT ?", { {} })
    tests.assertNil(sql)
    tests.assertContains(err, "table")
    sql, err = Sql.bind("SELECT ?, ?", { 1 })
    tests.assertNil(sql)
    tests.assertContains(err, "expected 2, got 1")
    sql, err = Sql.bind("SELECT '?'", { 1 })
    tests.assertContains(err, "expected 0, got 1")
    tests.assertNil((Sql.bind("SELECT 1", "nope")))
    -- identifiers
    tests.assertEquals(Sql.identifier("users.id"), "`users`.`id`")
    tests.assertError(function() Sql.identifier("users`; DROP") end, "invalid SQL identifier")
    tests.assertError(function() Sql.identifier("a..b") end, "invalid SQL identifier")
    tests.assertEquals(Sql.select_identifier("users.*"), "`users`.*")
    tests.assertEquals(Sql.select_identifier("users.name AS author"), "`users`.`name` AS `author`")
end

local function query_tests()
    local driver, log = fake_driver(function(sql)
        if sql:match("^SELECT") then return { { id = 1, name = "Ada", bio = ngx.null } } end
        return { affected_rows = 1, insert_id = 7, server_status = 2, warning_count = 0 }
    end)
    local db = MySQL.new(CONFIG, driver)
    local rows = db:query("SELECT * FROM users WHERE id = ?", { 1 })
    tests.assertEquals(#rows, 1)
    tests.assertEquals(rows[1].name, "Ada")
    tests.assertNil(rows[1].bio)
    tests.assertEquals(log.queries[1], "SELECT * FROM users WHERE id = 1")
    tests.assertEquals(log.opts.charset, "utf8mb4")
    tests.assertEquals(log.opts.database, "app")
    tests.assertTableEquals(log.timeouts, { 5000, 10000 })

    local result = db:execute("INSERT INTO users (name) VALUES (?)", { "Grace" })
    tests.assertEquals(result.affected_rows, 1)
    tests.assertEquals(result.insert_id, 7)
    -- every successful query returns its connection to the pool
    tests.assertEquals(log.connects, 2)
    tests.assertEquals(log.keepalives, 2)
    tests.assertEquals(log.closes, 0)
    tests.assertTableEquals(log.keepalive_args, { 10000, 100 })

    local tuned_driver, tuned_log = fake_driver()
    MySQL.new({ host = "h", database = "d", user = "u", max_idle_timeout = 500, pool_size = 7 }, tuned_driver)
        :execute("DO 1")
    tests.assertTableEquals(tuned_log.keepalive_args, { 500, 7 })

    local no_pool_driver, no_pool_log = fake_driver()
    MySQL.new({ host = "h", database = "d", user = "u", keepalive = false }, no_pool_driver):execute("DO 1")
    tests.assertEquals(no_pool_log.keepalives, 0)
    tests.assertEquals(no_pool_log.closes, 1)

    -- bind errors never reach the server
    local bad, bad_err, _, _, kind = db:query("SELECT ?", {})
    tests.assertNil(bad)
    tests.assertContains(bad_err, "binding count mismatch")
    tests.assertEquals(kind, "bind")
    tests.assertEquals(#log.queries, 2)

    tests.assertError(function() MySQL.new({ host = "h", user = "u" }, driver) end, "requires database")
end

local function error_tests()
    local driver, log = fake_driver(function(sql)
        if sql:match("dup") then return nil, "Duplicate entry 'a' for key 'users.email'", 1062, "23000" end
        if sql:match("timeout") then return nil, "timeout" end
        return { affected_rows = 1, insert_id = 0, server_status = 2 }
    end)
    local db = MySQL.new(CONFIG, driver)
    local result, err, errno, sqlstate, kind = db:execute("INSERT dup")
    tests.assertNil(result)
    tests.assertContains(err, "Duplicate entry")
    tests.assertEquals(errno, 1062)
    tests.assertEquals(sqlstate, "23000")
    tests.assertEquals(kind, "unique_violation")
    tests.assertTrue(MySQL.is_unique_violation(errno))
    -- a server error leaves the connection usable
    tests.assertEquals(log.keepalives, 1)

    local _, timeout_err, timeout_errno, _, timeout_kind = db:execute("SELECT timeout")
    tests.assertContains(timeout_err, "timeout")
    tests.assertNil(timeout_errno)
    tests.assertEquals(timeout_kind, "connection")
    -- a network error closes the connection instead of pooling it
    tests.assertEquals(log.keepalives, 1)
    tests.assertEquals(log.closes, 1)

    local down_driver, down_log = fake_driver()
    down_log.connect_error = "connection refused"
    local down = MySQL.new(CONFIG, down_driver)
    local rows, connect_err, _, _, connect_kind = down:query("SELECT 1")
    tests.assertNil(rows)
    tests.assertContains(connect_err, "connection refused")
    tests.assertEquals(connect_kind, "connection")
    tests.assertEquals(#down_log.queries, 0)

    -- a plain query that leaves a transaction open is never pooled
    local open_driver, open_log = fake_driver(function()
        return { affected_rows = 0, insert_id = 0, server_status = 3 }
    end)
    MySQL.new(CONFIG, open_driver):execute("BEGIN")
    tests.assertEquals(open_log.keepalives, 0)
    tests.assertEquals(open_log.closes, 1)
end

local function transaction_tests()
    local driver, log = fake_driver(function(sql)
        if sql:match("^SELECT") then return { { total = 2 } } end
        if sql:match("fail") then return nil, "boom", 1064, "42000" end
        local status = (sql == "COMMIT" or sql == "ROLLBACK") and 2 or 3
        return { affected_rows = 1, insert_id = 5, server_status = status }
    end)
    local db = MySQL.new(CONFIG, driver)

    local value, extra = db:transaction(function(tx)
        tests.assertTrue(tx:execute("INSERT INTO a VALUES (?)", { 1 }) ~= nil)
        local rows = tx:query("SELECT COUNT(*) AS total FROM a")
        return rows[1].total, "extra"
    end)
    tests.assertEquals(value, 2)
    tests.assertEquals(extra, "extra")
    tests.assertTableEquals(log.queries, {
        "START TRANSACTION", "INSERT INTO a VALUES (1)", "SELECT COUNT(*) AS total FROM a", "COMMIT",
    })
    -- one pinned connection, pooled after COMMIT
    tests.assertEquals(log.connects, 1)
    tests.assertEquals(log.keepalives, 1)

    tests.assertTrue(db:transaction(function(tx) tx:execute("DO 1") end))

    log.queries = {}
    local failed, err = db:transaction(function(tx)
        tx:execute("INSERT INTO a VALUES (1)")
        error("kaboom")
    end)
    tests.assertNil(failed)
    tests.assertContains(tostring(err), "kaboom")
    tests.assertEquals(log.queries[#log.queries], "ROLLBACK")
    tests.assertEquals(log.keepalives, 3)

    log.queries = {}
    local soft, soft_err = db:transaction(function(tx)
        local ok, query_err = tx:execute("INSERT fail")
        if not ok then return nil, query_err end
    end)
    tests.assertNil(soft)
    tests.assertContains(soft_err, "boom")
    tests.assertEquals(log.queries[#log.queries], "ROLLBACK")

    local aborted = db:transaction(function() return false end)
    tests.assertNil(aborted)

    -- tx handle is dead after the transaction ends
    local leaked
    db:transaction(function(tx) leaked = tx end)
    local after, after_err = leaked:query("SELECT 1")
    tests.assertNil(after)
    tests.assertContains(after_err, "finished")

    -- nested transactions use savepoints
    log.queries = {}
    db:transaction(function(tx)
        tx:transaction(function(inner) inner:execute("DO 1") end)
        tx:transaction(function() error("inner failure") end)
    end)
    tests.assertTableEquals(log.queries, {
        "START TRANSACTION", "SAVEPOINT crescent_sp_1", "DO 1", "RELEASE SAVEPOINT crescent_sp_1",
        "SAVEPOINT crescent_sp_2", "ROLLBACK TO SAVEPOINT crescent_sp_2", "COMMIT",
    })

    -- if ROLLBACK itself fails the connection is closed, never pooled
    local broken_driver, broken_log = fake_driver(function(sql)
        if sql == "ROLLBACK" then return nil, "closed" end
        return { affected_rows = 0, insert_id = 0, server_status = 3 }
    end)
    local broken = MySQL.new(CONFIG, broken_driver)
    tests.assertNil((broken:transaction(function() error("x") end)))
    tests.assertEquals(broken_log.keepalives, 0)
    tests.assertEquals(broken_log.closes, 1)

    -- failed COMMIT: rollback attempted, connection closed
    local commit_driver, commit_log = fake_driver(function(sql)
        if sql == "COMMIT" then return nil, "lost connection" end
        return { affected_rows = 0, insert_id = 0, server_status = 3 }
    end)
    local commit_db = MySQL.new(CONFIG, commit_driver)
    local committed, commit_err = commit_db:transaction(function(tx) tx:execute("DO 1") end)
    tests.assertNil(committed)
    tests.assertContains(commit_err, "lost connection")
    tests.assertEquals(commit_log.keepalives, 0)
    tests.assertEquals(commit_log.closes, 1)
end

local function manager_tests()
    Database.reset()
    tests.assertFalse(Database.is_configured())
    tests.assertError(function() Database.default() end, "not configured")
    local driver, log = fake_driver(function() return { { one = 1 } } end)
    local adapter = Database.configure(CONFIG, { driver = driver })
    tests.assertEquals(Database.default(), adapter)
    tests.assertEquals(Database.query("SELECT ?", { 1 })[1].one, 1)
    tests.assertEquals(log.queries[1], "SELECT 1")
    local rows = Database.table("users"):where("id", 3):get()
    tests.assertEquals(rows[1].one, 1)
    tests.assertEquals(log.queries[2], "SELECT * FROM `users` WHERE `id` = 3")
    tests.assertError(function() Database.configure({ driver = "postgres" }) end, "unsupported database driver")
    Database.reset()
end

assert(tests.runSuite("MySQL adapter", {
    bindings = binding_tests,
    queries = query_tests,
    errors = error_tests,
    transactions = transaction_tests,
    manager = manager_tests,
}))
