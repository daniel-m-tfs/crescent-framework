package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Model = require("crescent.model")

local function model_tests()
    local User = Model:extend({
        table = "users",
        fillable = { "name", "email", "password" },
        guarded = { "is_admin" },
        hidden = { "password" },
        timestamps = true,
        soft_deletes = true,
        validates = { name = { required = true, min_length = 3 } },
    })
    local user = User:new({
        name = "Ada",
        email = "ada@example.com",
        password = "secret",
        is_admin = true,
        ignored = true,
    })

    tests.assertEquals(User.table, "users")
    tests.assertEquals(user:get("name"), "Ada")
    tests.assertNil(user:get("is_admin"))
    tests.assertNil(user:get("ignored"))
    tests.assertNotNil(user:get("created_at"))
    tests.assertNotNil(user:get("updated_at"))
    tests.assertNil(user:to_table().password)
    tests.assertEquals(user:to_table().email, "ada@example.com")
    tests.assertTrue(user:validate())
    tests.assertFalse(user:trashed())
    tests.assertTrue(user:delete())
    tests.assertTrue(user:trashed())
    tests.assertTrue(user:restore())
    tests.assertFalse(user:trashed())

    local invalid = User:new({ name = "A" })
    local valid, errors = invalid:validate()
    tests.assertFalse(valid)
    tests.assertEquals(errors.name[1].code, "min_length")

    local Plain = Model:extend({ table = "plain" })
    local plain = Plain:new({ id = 1 })
    local deleted, delete_error = plain:delete()
    tests.assertNil(deleted)
    tests.assertContains(delete_error, "soft deletes")

    local statements = {}
    local adapter = {
        execute = function(self, sql, bindings)
            statements[#statements + 1] = { sql = sql, bindings = bindings }
            if sql:match("^INSERT") then return { insert_id = 42, affected = 1 } end
            return { affected = 1 }
        end,
    }
    local persisted = User:new({ name = "Grace", email = "grace@example.com" })
    tests.assertNotNil(persisted:save(adapter))
    tests.assertTrue(persisted.exists)
    tests.assertContains(statements[1].sql, "INSERT INTO `users`")
    tests.assertNotContains(statements[1].sql, "Grace")
    persisted:set("name", "Grace Hopper")
    tests.assertNotNil(persisted:save(adapter))
    tests.assertContains(statements[2].sql, "UPDATE `users`")

    local Post = Model:extend({ table = "posts", fillable = { "title", "user_id" } })
    local relation_sql
    local relation_adapter = {
        query = function(self, sql, bindings)
            relation_sql = sql
            return { { id = 7, title = "Hello", user_id = bindings[1] } }
        end,
        execute = function() return { insert_id = 1 } end,
    }
    local RelationUser = Model:extend({
        table = "users",
        relations = { posts = { type = "has_many", model = Post, foreign_key = "user_id" } },
    })
    local relation_user = RelationUser:new({ id = 4 })
    local posts = relation_user:relation("posts", relation_adapter)
    tests.assertEquals(#posts, 1)
    tests.assertEquals(posts[1]:get("title"), "Hello")
    tests.assertContains(relation_sql, "WHERE `user_id` = ?")

    local unique_adapter = {
        query = function() return { { id = 99 } } end,
        execute = function() return { insert_id = 43, affected = 1 } end,
    }
    local Duplicate = Model:extend({
        table = "users",
        fillable = { "email" },
        validates = { email = { required = true, unique = true } },
    })
    local duplicate, duplicate_errors = Duplicate:new({ email = "ada@example.com" }):save(unique_adapter)
    tests.assertNil(duplicate)
    tests.assertEquals(duplicate_errors.email[1].code, "unique")
end

assert(tests.runSuite("Model", { declarative_contract = model_tests }))