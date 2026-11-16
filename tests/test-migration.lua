package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Migrator = require("crescent.database.migration")
local DbCommand = require("cli.commands.db")

-- In-memory stand-in for the `migrations` table plus a statement log.
local function fake_database(options)
    options = options or {}
    local db = { rows = {}, statements = {}, next_id = 1 }
    function db:execute(sql, bindings)
        if sql:match("^CREATE TABLE IF NOT EXISTS `migrations`") then return { affected_rows = 0 } end
        if sql:match("^INSERT INTO `migrations`") then
            self.rows[#self.rows + 1] = { id = self.next_id, migration = bindings[1], batch = bindings[2] }
            self.next_id = self.next_id + 1
            return { affected_rows = 1, insert_id = self.next_id - 1 }
        end
        if sql:match("^DELETE FROM `migrations`") then
            for index, row in ipairs(self.rows) do
                if row.migration == bindings[1] then table.remove(self.rows, index) break end
            end
            return { affected_rows = 1 }
        end
        self.statements[#self.statements + 1] = sql
        if options.fail and sql:match(options.fail) then return nil, "ddl failed", 1064 end
        return { affected_rows = 0 }
    end
    function db:query(sql, bindings)
        if sql:match("FROM `migrations`") then
            local copy = {}
            for index, row in ipairs(self.rows) do copy[index] = row end
            return copy
        end
        return self:execute(sql, bindings)
    end
    return db
end

local function migration(name, up, down)
    return { name = name, up = up, down = down or function() return "DROP " .. name end }
end

local function batch_tests()
    local db = fake_database()
    local migrations = {
        migration("002_posts", function() return { sql = "CREATE TABLE posts", bindings = {} } end),
        migration("001_users", function() return { "CREATE TABLE users", "CREATE INDEX users_email" } end),
    }
    local runner = Migrator.new(db, { migrations = migrations })
    local result = runner:migrate()
    tests.assertEquals(result.batch, 1)
    tests.assertTableEquals(result.migrated, { "001_users", "002_posts" })
    tests.assertTableEquals(db.statements, { "CREATE TABLE users", "CREATE INDEX users_email", "CREATE TABLE posts" })
    tests.assertEquals(#db.rows, 2)
    tests.assertEquals(db.rows[1].batch, 1)

    tests.assertTableEquals(runner:migrate().migrated, {})

    migrations[#migrations + 1] = migration("003_tags", function() return "CREATE TABLE tags" end)
    local second = runner:migrate()
    tests.assertEquals(second.batch, 2)
    tests.assertTableEquals(second.migrated, { "003_tags" })

    local status = runner:status()
    tests.assertEquals(#status, 3)
    tests.assertTrue(status[3].ran)
    tests.assertEquals(status[3].batch, 2)

    -- rollback reverts only the last batch, in reverse order
    local rolled = runner:rollback()
    tests.assertEquals(rolled.batch, 2)
    tests.assertTableEquals(rolled.rolled_back, { "003_tags" })
    rolled = runner:rollback()
    tests.assertTableEquals(rolled.rolled_back, { "002_posts", "001_users" })
    tests.assertEquals(db.statements[#db.statements], "DROP 001_users")
    tests.assertEquals(#db.rows, 0)
    tests.assertTableEquals(runner:rollback().rolled_back, {})
    tests.assertFalse(runner:status()[1].ran)
end

local function failure_tests()
    local db = fake_database({ fail = "CREATE bad" })
    local runner = Migrator.new(db, { migrations = {
        migration("001_ok", function() return "CREATE ok" end),
        migration("002_bad", function() return "CREATE bad" end),
        migration("003_never", function() return "CREATE never" end),
    } })
    local result, err, info = runner:migrate()
    tests.assertNil(result)
    tests.assertContains(err, "002_bad")
    tests.assertContains(err, "ddl failed")
    tests.assertEquals(info.failed, "002_bad")
    tests.assertTableEquals(info.migrated, { "001_ok" })
    -- applied migrations are recorded, the failing one and later ones are not
    tests.assertEquals(#db.rows, 1)
    tests.assertEquals(db.rows[1].migration, "001_ok")
    tests.assertNil(db.statements[3])

    local raising = Migrator.new(fake_database(), { migrations = {
        migration("001_raise", function() error("oops") end),
    } })
    local _, raise_err = raising:migrate()
    tests.assertContains(raise_err, "oops")

    local empty = Migrator.new(fake_database(), { migrations = { migration("001_nil", function() end) } })
    local _, nil_err = empty:migrate()
    tests.assertContains(nil_err, "must return SQL")

    local noop = Migrator.new(fake_database(), { migrations = { migration("001_noop", function() return {} end) } })
    tests.assertTableEquals(noop:migrate().migrated, { "001_noop" })

    tests.assertError(function() Migrator.new(fake_database(), { table = "x; DROP" }) end, "invalid SQL identifier")
end

local function file_tests()
    local directory = "tmp/test-migrations-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000))
    os.execute("mkdir -p " .. directory)
    tests.assertFalse(DbCommand.make_migration("1bad"))
    tests.assertFalse(DbCommand.make_migration("bad-name"))
    local path = DbCommand.make_migration("create_users", { path = directory, timestamp = "20260101000000" })
    tests.assertEquals(path, directory .. "/20260101000000_create_users.lua")
    tests.assertFalse(DbCommand.make_migration("create_users", { path = directory, timestamp = "20260101000000" }))
    local file = io.open(directory .. "/20250101000000_first.lua", "w")
    file:write('return { up = function() return "CREATE first" end, down = function() return "DROP first" end }')
    file:close()
    file = io.open(directory .. "/README.txt", "w")
    file:write("ignored")
    file:close()

    local db = fake_database()
    local runner = Migrator.new(db, { path = directory })
    local entries = runner:discover()
    tests.assertEquals(#entries, 2)
    tests.assertEquals(entries[1].name, "20250101000000_first")
    local result = runner:migrate()
    tests.assertTableEquals(result.migrated, { "20250101000000_first", "20260101000000_create_users" })
    tests.assertEquals(db.statements[1], "CREATE first")
    tests.assertContains(db.statements[2], "CREATE TABLE `example`")
    tests.assertTableEquals(runner:rollback().rolled_back, { "20260101000000_create_users", "20250101000000_first" })

    -- the CLI functions work against an injected adapter
    tests.assertTrue(DbCommand.migrate({ adapter = db, path = directory }))
    tests.assertTrue(DbCommand.status({ adapter = db, path = directory }))
    tests.assertTrue(DbCommand.rollback({ adapter = db, path = directory }))
    os.execute("rm -rf " .. directory)
end

assert(tests.runSuite("Migrations", {
    batches = batch_tests,
    failures = failure_tests,
    files = file_tests,
}))
