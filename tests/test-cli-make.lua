package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local fs = require("cli.fs")
local Templates = require("cli.templates")
local Make = require("cli.commands.make")
local Crescent = require("crescent")
local json = require("crescent.json")

local MALICIOUS = { "../x", "a;rm -rf", "$(x)", "`x`", "a b", "x/y", "", "1abc", "a\nb", "-rf", string.rep("a", 65) }

local function temp_dir()
    local handle = io.popen("mktemp -d")
    local path = handle:read("*l")
    handle:close()
    return path
end

local function with_root(callback)
    local root = temp_dir()
    local previous = Make.root
    Make.root = root
    local ok, err = pcall(callback, root)
    Make.root = previous
    fs.execute("rm -rf " .. fs.shell_quote(root))
    if not ok then error(err, 0) end
end

local function quietly(callback, ...)
    local original = print
    print = function() end
    local ok, result = pcall(callback, ...)
    print = original
    if not ok then error(result, 0) end
    return result
end

local function assert_loads(path)
    local chunk, err = loadfile(path)
    tests.assertNotNil(chunk, "generated file does not compile: " .. path .. ": " .. tostring(err))
end

local function names()
    tests.assertEquals(Templates.snake("BlogPost"), "blog_post")
    tests.assertEquals(Templates.snake("blog-post"), "blog_post")
    tests.assertEquals(Templates.snake("HTTPClient"), "http_client")
    tests.assertEquals(Templates.pascal("blog_post"), "BlogPost")
    tests.assertEquals(Templates.plural("category"), "categories")
    tests.assertEquals(Templates.plural("box"), "boxes")
    tests.assertEquals(Templates.plural("user"), "users")
    tests.assertEquals(Templates.migration_table("create_products_table"), "products")
    tests.assertEquals(Templates.migration_table("add_email_to_users"), "users")
    tests.assertTrue(Templates.is_valid_name("User_profile-2"))
    for _, name in ipairs(MALICIOUS) do
        tests.assertFalse(Templates.is_valid_name(name), "accepted " .. name)
    end
    tests.assertFalse(Templates.is_valid_name(nil))
end

local function generators_write_loadable_files()
    with_root(function(root)
        quietly(function()
            tests.assertTrue(Make.controller("Order", "shop"))
            tests.assertTrue(Make.service("Order", "shop"))
            tests.assertTrue(Make.model("Order", "shop"))
            tests.assertTrue(Make.routes("Order", "shop"))
            tests.assertTrue(Make.middleware("RequireAuth"))
            tests.assertTrue(Make.middleware("Audit", "shop"))
            tests.assertTrue(Make.test("Order"))
        end)
        for _, relative in ipairs({
            "src/shop/controllers/order.lua", "src/shop/services/order.lua", "src/shop/models/order.lua",
            "src/shop/routes/order.lua", "src/middleware/require_auth.lua", "src/shop/middleware/audit.lua",
            "tests/test-order.lua",
        }) do
            assert_loads(fs.join(root, relative))
        end
        local model = fs.read(fs.join(root, "src/shop/models/order.lua"))
        tests.assertContains(model, "Model:extend({")
        tests.assertContains(model, 'table = "orders"')
        tests.assertContains(fs.read(fs.join(root, "src/shop/middleware/audit.lua")), 'require("src.shop.middleware.audit")')

        local middleware = dofile(fs.join(root, "src/middleware/require_auth.lua"))
        tests.assertEquals(middleware({}, function() return "next" end), "next")
    end)
end

local function never_overwrites()
    with_root(function(root)
        local path = fs.join(root, "src/shop/controllers/order.lua")
        quietly(function()
            tests.assertTrue(Make.controller("Order", "shop"))
            local file = io.open(path, "w")
            file:write("-- edited")
            file:close()
            tests.assertFalse(Make.controller("Order", "shop"))
        end)
        tests.assertEquals(fs.read(path), "-- edited")
    end)
end

local function rejects_malicious_names()
    with_root(function(root)
        quietly(function()
            for _, name in ipairs(MALICIOUS) do
                for _, generator in ipairs({ "controller", "service", "model", "routes", "middleware", "test", "migration", "module" }) do
                    tests.assertFalse(Make[generator](name), generator .. " accepted " .. name)
                end
                tests.assertFalse(Make.controller("Valid", name), "accepted module " .. name)
            end
        end)
        tests.assertEquals(#fs.list_files(root), 0, "nothing may be written for invalid names")
    end)
end

local function migration_file_format()
    with_root(function(root)
        local relative = quietly(Make.migration_file, "create_widgets_table", "20260101120000")
        tests.assertEquals(relative, "migrations/20260101120000_create_widgets_table.lua")
        local migration = dofile(fs.join(root, relative))
        tests.assertContains(migration.up(), "CREATE TABLE IF NOT EXISTS `widgets`")
        tests.assertEquals(migration.down(), "DROP TABLE IF EXISTS `widgets`")
        tests.assertNil(quietly(Make.migration_file, "create_widgets_table", "20260101120000"))

        local alter = dofile(fs.join(root, quietly(Make.migration_file, "add_price_to_widgets", "20260101120001")))
        tests.assertContains(alter.up(), "ALTER TABLE `widgets` ADD COLUMN")
        tests.assertContains(alter.down(), "ALTER TABLE `widgets` DROP COLUMN")
    end)
end

-- Fake adapter: records statements and answers SELECTs with `rows`.
local function fake_db(rows)
    local db = { statements = {} }
    function db:query(sql, bindings)
        self.statements[#self.statements + 1] = { sql = sql, bindings = bindings }
        return rows
    end
    function db:execute(sql, bindings)
        self.statements[#self.statements + 1] = { sql = sql, bindings = bindings }
        return { insert_id = 7, affected_rows = 1 }
    end
    return db
end

local function call(app, method, path, body)
    local writer = { headers = {} }
    app:handle({ method = method, path = path, headers = {}, query = {}, body = body }, writer)
    return writer.status, writer.body ~= "" and json.decode(writer.body) or nil
end

local function crud_module_works()
    with_root(function(root)
        tests.assertTrue(quietly(Make.module, "Gadget"))
        for _, relative in ipairs({ "src/gadget/init.lua", "src/gadget/models/gadget.lua",
            "src/gadget/services/gadget.lua", "src/gadget/controllers/gadget.lua", "src/gadget/routes/gadget.lua",
            "tests/test-gadget-module.lua" }) do
            assert_loads(fs.join(root, relative))
        end
        tests.assertFalse(quietly(Make.module, "Gadget"), "module must not be generated twice")

        local saved_path = package.path
        package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
        local ok, err = pcall(function()
            local app = Crescent.new({ environment = "test", debug = true })
            require("src.gadget").register(app)
            tests.assertEquals(app:route("gadgets.show"), "/gadgets/{id}")

            local status = call(app, "GET", "/gadgets")
            tests.assertEquals(status, 503)

            app.db = fake_db({})
            local list_status, list = call(app, "GET", "/gadgets")
            tests.assertEquals(list_status, 200)
            tests.assertEquals(#list.data, 0)
            tests.assertEquals(call(app, "GET", "/gadgets/9"), 404)

            local invalid_status, invalid = call(app, "POST", "/gadgets", {})
            tests.assertEquals(invalid_status, 422)
            tests.assertEquals(invalid.code, "validation_failed")

            local created_status, created = call(app, "POST", "/gadgets", { name = "Lamp", admin = true })
            tests.assertEquals(created_status, 201)
            tests.assertEquals(created.data.id, 7)
            tests.assertEquals(created.data.name, "Lamp")
            tests.assertNil(created.data.admin, "fillable must filter unknown attributes")
            tests.assertContains(app.db.statements[#app.db.statements].sql, "gadgets")

            app.db = fake_db({ { id = 3, name = "Old", created_at = "2026-01-01 00:00:00" } })
            local updated_status, updated = call(app, "PUT", "/gadgets/3", { name = "New" })
            tests.assertEquals(updated_status, 200)
            tests.assertEquals(updated.data.name, "New")
            tests.assertEquals(updated.data.created_at, "2026-01-01 00:00:00")
            tests.assertEquals(call(app, "DELETE", "/gadgets/3"), 204)
        end)
        package.path = saved_path
        for name in pairs(package.loaded) do
            if name:match("^src%.gadget") then package.loaded[name] = nil end
        end
        if not ok then error(err, 0) end
    end)
end

local function launcher_rejects_bad_input()
    local function status(command)
        return fs.execute(command .. " >/dev/null 2>&1")
    end
    tests.assertTrue(status("./bin/crescent help"))
    tests.assertFalse(status("./bin/crescent make:action '../x'"))
    tests.assertFalse(status("./bin/crescent make:action"))
    tests.assertFalse(status("./bin/crescent no-such-command"))
    tests.assertFalse(fs.exists("src/x"))
end

assert(tests.runSuite("CLI generators", {
    names = names,
    generators_write_loadable_files = generators_write_loadable_files,
    never_overwrites = never_overwrites,
    rejects_malicious_names = rejects_malicious_names,
    migration_file_format = migration_file_format,
    crud_module_works = crud_module_works,
    launcher_rejects_bad_input = launcher_rejects_bad_input,
}))
