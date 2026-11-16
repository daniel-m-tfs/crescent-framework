package.path = "./?.lua;./?/init.lua;" .. package.path

-- Runs against a real MySQL only when credentials are in the environment:
--   DB_PASSWORD=... DB_USER=root DB_HOST=127.0.0.1 DB_PORT=3306 \
--   DB_TEST_NAME=newcrescent_test lua cli.lua test mysql-integration
-- The database must exist; tables are created and dropped by the test.
local password = os.getenv("DB_PASSWORD")
if not password or password == "" then
    print("SKIP MySQL integration: set DB_PASSWORD (and DB_USER/DB_HOST/DB_PORT/DB_TEST_NAME) to run")
    return
end

local tests = require("crescent.utils.tests")
local Database = require("crescent.database")
local Migrator = require("crescent.database.migration")
local Model = require("crescent.model")

local db = Database.configure({
    host = os.getenv("DB_HOST") or "127.0.0.1",
    port = tonumber(os.getenv("DB_PORT") or "3306"),
    database = os.getenv("DB_TEST_NAME") or "newcrescent_test",
    user = os.getenv("DB_USER") or "root",
    password = password,
})

local MIGRATIONS_TABLE = "crescent_test_migrations"

local migrations = {
    {
        name = "001_create_it_users",
        up = function()
            return [[
                CREATE TABLE `it_users` (
                    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    `name` VARCHAR(100) NOT NULL,
                    `email` VARCHAR(191) NOT NULL,
                    `bio` TEXT NULL,
                    `created_at` DATETIME NULL,
                    `updated_at` DATETIME NULL,
                    `deleted_at` DATETIME NULL,
                    UNIQUE KEY `email` (`email`)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
            ]]
        end,
        down = function() return "DROP TABLE `it_users`" end,
    },
    {
        name = "002_create_it_posts",
        up = function()
            return {
                [[CREATE TABLE `it_posts` (
                    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                    `it_user_id` BIGINT UNSIGNED NOT NULL,
                    `title` VARCHAR(200) NOT NULL
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                "CREATE INDEX `it_posts_user` ON `it_posts` (`it_user_id`)",
            }
        end,
        down = function() return "DROP TABLE `it_posts`" end,
    },
}

local runner = Migrator.new(db, { table = MIGRATIONS_TABLE, migrations = migrations })

local Post = Model:extend({ table = "it_posts", fillable = { "it_user_id", "title" } })
local User = Model:extend({
    table = "it_users",
    fillable = { "name", "email", "bio" },
    hidden = { "deleted_at" },
    timestamps = true,
    soft_deletes = true,
    validates = { name = { required = true }, email = { required = true, email = true } },
    relations = { posts = { type = "has_many", model = Post } },
})

local function cleanup()
    db:execute("DROP TABLE IF EXISTS `it_posts`")
    db:execute("DROP TABLE IF EXISTS `it_users`")
    db:execute("DROP TABLE IF EXISTS `" .. MIGRATIONS_TABLE .. "`")
end

local function migration_tests()
    local result, err = runner:migrate()
    tests.assertNotNil(result, err)
    tests.assertTableEquals(result.migrated, { "001_create_it_users", "002_create_it_posts" })
    tests.assertTableEquals(runner:migrate().migrated, {})
    local status = runner:status()
    tests.assertTrue(status[1].ran and status[2].ran)
    tests.assertTableEquals(runner:rollback().rolled_back, { "002_create_it_posts", "001_create_it_users" })
    tests.assertNotNil(runner:migrate())
end

local function crud_tests()
    local ada, errors = User:create({ name = "Ada", email = "ada@example.com", bio = "It's 50% \"quoted\" ?" })
    tests.assertNotNil(ada, type(errors) == "table" and "validation failed" or tostring(errors))
    tests.assertTrue(ada:get("id") > 0)

    local found = User:find(ada:get("id"))
    tests.assertEquals(found:get("bio"), "It's 50% \"quoted\" ?")
    tests.assertNotNil(found:get("created_at"))

    tests.assertNotNil(found:update({ name = "Ada Lovelace" }))
    found:set("bio", nil)
    tests.assertNotNil(found:save())
    local reloaded = User:find(ada:get("id"))
    tests.assertEquals(reloaded:get("name"), "Ada Lovelace")
    tests.assertNil(reloaded:get("bio"))

    local invalid, invalid_errors = User:create({ name = "", email = "x" })
    tests.assertNil(invalid)
    tests.assertNotNil(invalid_errors.name)

    tests.assertEquals(User:query():where("email", "LIKE", "%@example.com"):count(), 1)
    tests.assertTrue(reloaded:delete())
    tests.assertNil(User:find(ada:get("id")))
    tests.assertEquals(#User:only_trashed():get(), 1)
    tests.assertTrue(reloaded:restore())
    tests.assertNotNil(User:find(ada:get("id")))
end

local function unique_tests()
    local duplicate, errors = User:create({ name = "Other", email = "ada@example.com" })
    tests.assertNil(duplicate)
    tests.assertEquals(errors.email[1].code, "unique")
    local _, err, errno, _, kind = db:execute("INSERT INTO `it_users` (`name`, `email`) VALUES (?, ?)", { "x", "ada@example.com" })
    tests.assertContains(err, "Duplicate")
    tests.assertEquals(errno, 1062)
    tests.assertEquals(kind, "unique_violation")
end

local function transaction_tests()
    local ok, err = Database.transaction(function(tx)
        assert(User:create({ name = "Tx", email = "tx@example.com" }, tx))
        error("rollback please")
    end)
    tests.assertNil(ok)
    tests.assertContains(tostring(err), "rollback please")
    tests.assertNil(User:where("email", "tx@example.com"):first())

    local created = Database.transaction(function(tx)
        return User:create({ name = "Tx", email = "tx@example.com" }, tx)
    end)
    tests.assertNotNil(created)
    tests.assertNotNil(User:where("email", "tx@example.com"):first())
end

local function eager_loading_tests()
    local users = User:all()
    for index, user in ipairs(users) do
        Post:create({ it_user_id = user:get("id"), title = "Post " .. index })
        Post:create({ it_user_id = user:get("id"), title = "Another " .. index })
    end
    local loaded = User:query():with("posts"):order_by("id"):get()
    tests.assertEquals(#loaded, #users)
    for _, user in ipairs(loaded) do
        tests.assertEquals(#user:get("posts"), 2)
        tests.assertEquals(user:get("posts")[1]:get("it_user_id"), user:get("id"))
    end
    tests.assertNotNil(loaded[1]:to_table().posts)
    tests.assertNil(loaded[1]:to_table().deleted_at)
end

local ping, ping_err = db:query("SELECT 1 AS ok")
if not ping then error("MySQL integration: cannot reach the database: " .. tostring(ping_err)) end

cleanup()
local ok = tests.runSuite("MySQL integration", {
    a_migrations = migration_tests,
    b_crud = crud_tests,
    c_unique = unique_tests,
    d_transactions = transaction_tests,
    e_eager_loading = eager_loading_tests,
})
cleanup()
assert(ok)
