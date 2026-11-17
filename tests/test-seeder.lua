package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Seeder = require("crescent.database.seeder")

local function fake_adapter()
    local adapter = { committed = 0, rolled_back = 0 }
    function adapter:transaction(fn)
        local results = { pcall(fn, self) }
        local ok, first, second = results[1], results[2], results[3]
        if not ok then self.rolled_back = self.rolled_back + 1 return nil, first end
        if first == false or (first == nil and second ~= nil) then
            self.rolled_back = self.rolled_back + 1
            return nil, second or "aborted"
        end
        self.committed = self.committed + 1
        return true
    end
    return adapter
end

local function runs_in_order_each_in_a_transaction()
    local order = {}
    local adapter = fake_adapter()
    local seeder = Seeder.new(adapter, { seeds = {
        { name = "02_posts", run = function(db) order[#order + 1] = "posts"; tests.assertEquals(db, adapter) end },
        { name = "01_users", run = function() order[#order + 1] = "users" end },
    } })
    local result = assert(seeder:run())
    tests.assertTableEquals(order, { "users", "posts" })
    tests.assertTableEquals(result.seeded, { "01_users", "02_posts" })
    tests.assertEquals(adapter.committed, 2)
end

local function stops_and_rolls_back_on_failure()
    local adapter = fake_adapter()
    local ran_after = false
    local seeder = Seeder.new(adapter, { seeds = {
        { name = "01_ok", run = function() end },
        { name = "02_boom", run = function() error("bad data") end },
        { name = "03_after", run = function() ran_after = true end },
    } })
    local result, err, info = seeder:run()
    tests.assertNil(result)
    tests.assertContains(err, "02_boom")
    tests.assertContains(err, "bad data")
    tests.assertTableEquals(info.seeded, { "01_ok" })
    tests.assertFalse(ran_after)
    tests.assertEquals(adapter.rolled_back, 1)

    local soft = Seeder.new(fake_adapter(), { seeds = { { name = "x", run = function() return nil, "nope" end } } })
    local none, soft_err = soft:run()
    tests.assertNil(none)
    tests.assertContains(soft_err, "nope")
end

local function runs_a_single_seeder_by_name()
    local ran = {}
    local seeder = Seeder.new(fake_adapter(), { seeds = {
        { name = "users", run = function() ran[#ran + 1] = "users" end },
        { name = "posts", run = function() ran[#ran + 1] = "posts" end },
    } })
    assert(seeder:run("posts"))
    tests.assertTableEquals(ran, { "posts" })
    local missing, err = seeder:run("comments")
    tests.assertNil(missing)
    tests.assertContains(err, "not found")
    local invalid, invalid_err = seeder:run("../etc/passwd")
    tests.assertNil(invalid)
    tests.assertContains(invalid_err, "invalid seeder name")
end

local function loads_files_from_disk()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local file = assert(io.open(dir .. "/01_demo.lua", "w"))
    file:write("return function(db) db.touched = true end\n")
    file:close()
    local broken = assert(io.open(dir .. "/02_broken.lua", "w"))
    broken:write("return 42\n")
    broken:close()

    local adapter = fake_adapter()
    local result, err = Seeder.new(adapter, { path = dir }):run("01_demo")
    tests.assertNotNil(result, err)
    tests.assertTrue(adapter.touched)
    local _, broken_err = Seeder.new(adapter, { path = dir }):run("02_broken")
    tests.assertContains(broken_err, "must return a function")
    os.execute("rm -rf '" .. dir .. "'")
end

local function make_seeder_validates_and_never_overwrites()
    local Db = require("cli.commands.db")
    local dir = os.tmpname()
    os.remove(dir)
    local path = Db.make_seeder("demo_users", { path = dir })
    tests.assertEquals(path, dir .. "/demo_users.lua")
    tests.assertNotNil(loadfile(path), "generated seeder must compile")
    tests.assertFalse(Db.make_seeder("demo_users", { path = dir }), "must not overwrite")
    tests.assertTrue(Db.make_seeder("01_admin_user", { path = dir }), "numeric prefixes order seeders")
    tests.assertFalse(Db.make_seeder("../x", { path = dir }))
    tests.assertFalse(Db.make_seeder("a;rm -rf /", { path = dir }))
    os.execute("rm -rf '" .. dir .. "'")
end

assert(tests.runSuite("Seeder", {
    runs_in_order_each_in_a_transaction = runs_in_order_each_in_a_transaction,
    stops_and_rolls_back_on_failure = stops_and_rolls_back_on_failure,
    runs_a_single_seeder_by_name = runs_a_single_seeder_by_name,
    loads_files_from_disk = loads_files_from_disk,
    make_seeder_validates_and_never_overwrites = make_seeder_validates_and_never_overwrites,
}))
