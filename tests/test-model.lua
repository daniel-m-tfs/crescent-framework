package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Model = require("crescent.model")
local Database = require("crescent.database")
local Relations = require("crescent.model.relations")

-- Fake adapter: `routes` is a list of { pattern, function(sql, bindings) }.
local function fake_adapter(routes)
    local adapter = { calls = {} }
    local function dispatch(self, sql, bindings)
        self.calls[#self.calls + 1] = { sql = sql, bindings = bindings }
        for _, route in ipairs(routes or {}) do
            if sql:match(route[1]) then return route[2](sql, bindings) end
        end
        if sql:match("^SELECT") then return {} end
        return { affected_rows = 1, insert_id = 0 }
    end
    adapter.query = dispatch
    adapter.execute = dispatch
    return adapter
end

local function attribute_tests()
    local User = Model:extend({
        table = "users",
        fillable = { "name", "email", "password" },
        guarded = { "is_admin" },
        hidden = { "password" },
        timestamps = true,
        soft_deletes = true,
        validates = { name = { required = true, min_length = 3 } },
    })
    local user = User:new({ name = "Ada", email = "ada@example.com", password = "secret", is_admin = true, ignored = true })
    tests.assertEquals(User.table, "users")
    tests.assertEquals(user:get("name"), "Ada")
    tests.assertEquals(user.name, "Ada")
    tests.assertNil(user:get("is_admin"))
    tests.assertNil(user:get("ignored"))
    tests.assertNotNil(user:get("created_at"))
    tests.assertNil(user:to_table().password)
    tests.assertEquals(user:toTable().email, "ada@example.com")
    tests.assertFalse(user.exists)
    tests.assertTrue(user:validate())
    tests.assertFalse(user:trashed())
    user.nickname = "ada"
    tests.assertEquals(user.attributes.nickname, "ada")

    local valid, errors = User:new({ name = "A" }):validate()
    tests.assertFalse(valid)
    tests.assertEquals(errors.name[1].code, "min_length")

    -- rows from the database bypass fillable and are persisted
    tests.assertEquals(User:hydrate({ id = "42" }):get("id"), 42, "integer ids from BIGINT strings become numbers")
    tests.assertEquals(User:hydrate({ id = "9007199254740993" }):get("id"), "9007199254740993", "ids beyond 2^53 stay strings")
    tests.assertEquals(User:hydrate({ id = "007" }):get("id"), "007", "non-canonical ids are untouched")
    tests.assertEquals(User:hydrate({ team_id = "5", phone = "5" }):get("team_id"), 5, "*_id columns are normalized too")
    tests.assertEquals(User:hydrate({ phone = "5" }):get("phone"), "5", "other columns keep the driver's type")
    local Cast = Model:extend({ table = "casts", casts = { external_id = "string", active = "boolean", price = "number" } })
    local cast = Cast:hydrate({ external_id = "123", active = 1, price = "9.90" })
    tests.assertEquals(cast:get("external_id"), "123")
    tests.assertEquals(cast:get("active"), true)
    tests.assertEquals(cast:get("price"), 9.9)
    local hydrated = User:hydrate({ id = 1, name = "Ada", is_admin = 1 })
    tests.assertTrue(hydrated.exists)
    tests.assertEquals(hydrated:get("is_admin"), 1)
    tests.assertFalse(hydrated:is_dirty())
    hydrated:set("name", "Ada L.")
    hydrated:set("is_admin", nil)
    tests.assertTrue(hydrated:is_dirty("name"))
    tests.assertEquals(hydrated:get_dirty().is_admin, Database.NULL)

    tests.assertError(function() Model:extend({ table = "users; DROP" }) end, "invalid SQL identifier")
    tests.assertEquals(Relations.singularize("categories"), "category")
    tests.assertEquals(Relations.singularize("addresses"), "address")
    tests.assertEquals(Relations.singularize("people"), "person")
    tests.assertEquals(Relations.singularize("users"), "user")
    tests.assertEquals(Relations.singularize("status"), "statu")
    tests.assertEquals(Relations.singularize("class"), "class")
end

local function persistence_tests()
    local events = {}
    local User = Model:extend({
        table = "users",
        fillable = { "name", "email" },
        timestamps = true,
        before_save = function(model) events[#events + 1] = "before_save" end,
        before_create = function(model) events[#events + 1] = "before_create" end,
        after_create = function(model) events[#events + 1] = "after_create" end,
        before_update = function(model) events[#events + 1] = "before_update" end,
        after_update = function(model) events[#events + 1] = "after_update" end,
        after_save = function(model) events[#events + 1] = "after_save" end,
        before_delete = function(model) events[#events + 1] = "before_delete" end,
        after_delete = function(model) events[#events + 1] = "after_delete" end,
    })
    local adapter = fake_adapter({
        { "^INSERT", function() return { affected_rows = 1, insert_id = 42 } end },
        { "^SELECT", function() return { { id = 42, name = "Grace", email = "g@x.io" } } end },
    })

    local user, errors = User:create({ name = "Grace", email = "grace@example.com", id = 99 }, adapter)
    tests.assertNil(errors)
    tests.assertTrue(user.exists)
    tests.assertEquals(user:get("id"), 42)
    tests.assertEquals(adapter.calls[1].sql, "INSERT INTO `users` (`created_at`, `email`, `name`, `updated_at`) VALUES (?, ?, ?, ?)")
    tests.assertNotContains(adapter.calls[1].sql, "Grace")
    tests.assertTableEquals(events, { "before_save", "before_create", "after_create", "after_save" })

    -- unchanged models issue no UPDATE
    tests.assertEquals(user:save(adapter), user)
    tests.assertEquals(#adapter.calls, 1)

    -- only dirty columns are written, never the primary key
    events = {}
    user:set("name", "Grace Hopper")
    user:set("id", 1000)
    tests.assertNotNil(user:save(adapter))
    local update = adapter.calls[2]
    tests.assertEquals(update.sql, "UPDATE `users` SET `name` = ?, `updated_at` = ? WHERE `id` = ?")
    tests.assertEquals(update.bindings[1], "Grace Hopper")
    tests.assertEquals(update.bindings[3], 42)
    tests.assertEquals(user:get("id"), 42)
    tests.assertTableEquals(events, { "before_save", "before_update", "after_update", "after_save" })

    -- update() honours fillable
    user:update({ email = "new@x.io", is_admin = true }, adapter)
    tests.assertNotContains(adapter.calls[3].sql, "is_admin")
    tests.assertContains(adapter.calls[3].sql, "`email` = ?")

    -- hard delete
    events = {}
    tests.assertTrue(user:delete(adapter))
    tests.assertEquals(adapter.calls[4].sql, "DELETE FROM `users` WHERE `id` = ?")
    tests.assertFalse(user.exists)
    tests.assertTableEquals(events, { "before_delete", "after_delete" })
    local again, again_err = user:delete(adapter)
    tests.assertNil(again)
    tests.assertContains(again_err, "does not exist")

    -- finders hydrate
    local found = User:find(42, adapter)
    tests.assertTrue(found.exists)
    tests.assertEquals(found:get("name"), "Grace")
    tests.assertEquals(adapter.calls[5].sql, "SELECT * FROM `users` WHERE `users`.`id` = ? LIMIT 1")
    local all = User:query(adapter):where("name", "LIKE", "G%"):order_by("id"):get()
    tests.assertEquals(#all, 1)
    tests.assertTrue(all[1].exists)

    local empty = fake_adapter()
    tests.assertNil(User:find(1, empty))
    local ok, err = pcall(function() User:find_or_fail(1, empty) end)
    tests.assertFalse(ok)
    tests.assertTrue(Model.is_not_found(err))
    tests.assertEquals(err.status, 404)

    -- a before_* hook returning false aborts
    local Locked = Model:extend({ table = "locked", before_save = function() return false end })
    local locked, locked_err = Locked:create({ a = 1 }, adapter)
    tests.assertNil(locked)
    tests.assertContains(locked_err, "before_save")

    -- the default database is used when no adapter is passed
    Database.set_default(adapter)
    local default_user = User:create({ name = "Default" })
    tests.assertEquals(default_user:get("id"), 42)
    Database.reset()
end

local function soft_delete_tests()
    local Post = Model:extend({ table = "posts", soft_deletes = true })
    local adapter = fake_adapter({
        { "^SELECT", function() return { { id = 1, title = "Hi" } } end },
    })
    local post = Post:hydrate({ id = 1, title = "Hi" })
    tests.assertTrue(post:delete(adapter))
    tests.assertEquals(adapter.calls[1].sql, "UPDATE `posts` SET `deleted_at` = ? WHERE `id` = ?")
    tests.assertTrue(post:trashed())
    tests.assertTrue(post.exists)
    tests.assertTrue(post:restore(adapter))
    tests.assertEquals(adapter.calls[2].bindings[1], Database.NULL)
    tests.assertFalse(post:trashed())
    tests.assertTrue(post:force_delete(adapter))
    tests.assertEquals(adapter.calls[3].sql, "DELETE FROM `posts` WHERE `id` = ?")

    tests.assertEquals((Post:query():to_sql()), "SELECT * FROM `posts` WHERE `posts`.`deleted_at` IS NULL")
    tests.assertEquals((Post:where("a", 1):or_where("b", 2):to_sql()),
        "SELECT * FROM `posts` WHERE (`a` = ? OR `b` = ?) AND `posts`.`deleted_at` IS NULL")
    tests.assertEquals((Post:with_trashed():to_sql()), "SELECT * FROM `posts`")
    tests.assertEquals((Post:only_trashed():to_sql()), "SELECT * FROM `posts` WHERE `posts`.`deleted_at` IS NOT NULL")
    tests.assertEquals((Post:query():to_count_sql()), "SELECT COUNT(*) AS `aggregate` FROM `posts` WHERE `posts`.`deleted_at` IS NULL")

    -- mass delete on a soft-delete model is an UPDATE, and still needs a WHERE
    Post:where("id", 5):delete(adapter)
    tests.assertEquals(adapter.calls[4].sql, "UPDATE `posts` SET `deleted_at` = ? WHERE `id` = ? AND `posts`.`deleted_at` IS NULL")
    tests.assertError(function() Post:query():delete(adapter) end, "requires at least one where")

    local Plain = Model:extend({ table = "plain" })
    local _, restore_err = Plain:hydrate({ id = 1 }):restore(adapter)
    tests.assertContains(restore_err, "soft deletes")
end

local function validation_tests()
    local User = Model:extend({
        table = "users",
        fillable = { "email", "name" },
        validates = { email = { required = true, email = true, unique = true } },
    })
    local taken = fake_adapter({ { "^SELECT", function() return { { id = 99 } } end } })
    local user, errors = User:create({ email = "ada@example.com" }, taken)
    tests.assertNil(user)
    tests.assertEquals(errors.email[1].code, "unique")
    tests.assertEquals(taken.calls[1].sql, "SELECT `id` FROM `users` WHERE `email` = ? LIMIT 1")
    tests.assertEquals(#taken.calls, 1)

    local invalid, invalid_errors = User:create({ email = "nope" }, taken)
    tests.assertNil(invalid)
    tests.assertEquals(invalid_errors.email[1].code, "email")

    -- existing rows exclude themselves and only re-check changed values
    local free = fake_adapter()
    local existing = User:hydrate({ id = 5, email = "a@b.io" })
    existing:set("name", "x")
    tests.assertNotNil(existing:save(free))
    tests.assertEquals(#free.calls, 1)
    existing:set("email", "c@d.io")
    existing:save(free)
    tests.assertEquals(free.calls[2].sql, "SELECT `id` FROM `users` WHERE `email` = ? AND `id` != ? LIMIT 1")

    -- a duplicate-key error from the database becomes a validation error
    local race = fake_adapter({
        { "^INSERT", function() return nil, "Duplicate entry 'a@b.io' for key 'users.email'", 1062, "23000", "unique_violation" end },
    })
    local raced, raced_errors = User:create({ email = "a@b.io" }, race)
    tests.assertNil(raced)
    tests.assertEquals(raced_errors.email[1].code, "unique")
    local Plain = Model:extend({ table = "tags" })
    local _, plain_errors = Plain:create({ slug = "x" }, fake_adapter({
        { "^INSERT", function() return nil, "Duplicate entry 'x' for key 'PRIMARY'", 1062 end },
    }))
    tests.assertEquals(plain_errors._database[1].code, "unique")

    -- other database errors pass through
    local _, db_err, errno = Plain:create({ slug = "y" }, fake_adapter({
        { "^INSERT", function() return nil, "table missing", 1146 end },
    }))
    tests.assertEquals(db_err, "table missing")
    tests.assertEquals(errno, 1146)
end

local function relation_tests()
    local Comment = Model:extend({ table = "comments", soft_deletes = true })
    local Profile = Model:extend({ table = "profiles" })
    local Post = Model:extend({
        table = "posts",
        relations = {
            comments = { type = "has_many", model = Comment },
            author = { type = "belongs_to", model = function() return package.loaded["test.user"] end, foreign_key = "user_id" },
        },
    })
    local User = Model:extend({
        table = "users",
        relations = {
            posts = { type = "has_many", model = Post },
            profile = { type = "has_one", model = Profile },
        },
    })
    package.loaded["test.user"] = User

    local adapter = fake_adapter({
        { "FROM `users`", function()
            return { { id = 1, name = "Ada" }, { id = 2, name = "Grace" }, { id = 3, name = "Linus" } }
        end },
        { "FROM `posts`", function()
            return { { id = 10, user_id = 1 }, { id = 11, user_id = 1 }, { id = 12, user_id = 2 } }
        end },
        { "FROM `profiles`", function() return { { id = 7, user_id = 2, bio = "hi" } } end },
        { "FROM `comments`", function() return { { id = 100, post_id = 10 }, { id = 101, post_id = 12 } } end },
    })

    local users = User:query(adapter):with("posts.comments", "profile"):get()
    -- 1 query for users + exactly one per relation (no N+1)
    tests.assertEquals(#adapter.calls, 4)
    tests.assertEquals(adapter.calls[2].sql, "SELECT * FROM `posts` WHERE `user_id` IN (?, ?, ?)")
    tests.assertTableEquals(adapter.calls[2].bindings, { 1, 2, 3 })
    tests.assertEquals(adapter.calls[3].sql, "SELECT * FROM `comments` WHERE `post_id` IN (?, ?, ?) AND `comments`.`deleted_at` IS NULL")
    tests.assertEquals(adapter.calls[4].sql, "SELECT * FROM `profiles` WHERE `user_id` IN (?, ?, ?)")

    tests.assertEquals(#users[1]:get("posts"), 2)
    tests.assertEquals(#users[2]:get("posts"), 1)
    tests.assertEquals(#users[3]:get("posts"), 0)
    tests.assertEquals(#users[1]:get("posts")[1]:get("comments"), 1)
    tests.assertNil(users[1]:get("profile"))
    tests.assertEquals(users[2]:get("profile"):get("bio"), "hi")
    tests.assertEquals(users[2].profile:get("bio"), "hi")
    -- accessing loaded relations issues no more queries
    tests.assertEquals(#adapter.calls, 4)

    local serialized = users[1]:to_table()
    tests.assertEquals(#serialized.posts, 2)
    tests.assertEquals(serialized.posts[1].comments[1].id, 100)
    tests.assertNil(serialized.profile)

    -- belongs_to with deduplicated keys, and constraints on the relation query
    local posts_adapter = fake_adapter({
        { "FROM `posts`", function() return { { id = 10, user_id = 1 }, { id = 11, user_id = 1 }, { id = 12 } } end },
        { "FROM `users`", function() return { { id = 1, name = "Ada" } } end },
    })
    local posts = Post:query(posts_adapter):with({ author = function(q) q:select("id", "name") end }):get()
    tests.assertEquals(#posts_adapter.calls, 2)
    tests.assertEquals(posts_adapter.calls[2].sql, "SELECT `id`, `name` FROM `users` WHERE `id` IN (?)")
    tests.assertEquals(posts[2]:get("author"):get("name"), "Ada")
    tests.assertNil(posts[3]:get("author"))

    -- lazy relation via get() and relation()
    local lazy_adapter = fake_adapter({ { "FROM `posts`", function() return { { id = 10, user_id = 4 } } end } })
    local user = User:hydrate({ id = 4 })
    tests.assertEquals(#user:relation("posts", lazy_adapter), 1)
    tests.assertEquals(lazy_adapter.calls[1].sql, "SELECT * FROM `posts` WHERE `user_id` IN (?)")
    Database.set_default(lazy_adapter)
    local fresh = User:hydrate({ id = 4 })
    tests.assertEquals(#fresh:get("posts"), 1)
    fresh:get("posts")
    tests.assertEquals(#lazy_adapter.calls, 2)
    Database.reset()

    -- empty parent sets and missing keys issue no query
    local idle = fake_adapter()
    local orphan = User:hydrate({ name = "no id" })
    orphan:load(idle, "posts")
    tests.assertEquals(#idle.calls, 0)
    tests.assertTableEquals(orphan:get("posts"), {})

    local bad = User:hydrate({ id = 1 })
    local ok, err = bad:load(idle, "missing")
    tests.assertNil(ok)
    tests.assertContains(err, "unknown relation")
end

assert(tests.runSuite("Model", {
    attributes = attribute_tests,
    persistence = persistence_tests,
    soft_deletes = soft_delete_tests,
    validation = validation_tests,
    relations = relation_tests,
}))
