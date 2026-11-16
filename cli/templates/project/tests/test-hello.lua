package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local json = require("crescent.json")

local function app()
    local instance = Crescent.new({ environment = "test", debug = true, root = ".", logger = function() end })
    require("src.hello").register(instance)
    return instance
end

local function get(instance, path, query)
    local writer = { headers = {} }
    instance:handle({ method = "GET", path = path, headers = {}, query = query or {} }, writer)
    return writer
end

local function home_page_renders()
    local writer = get(app(), "/")
    tests.assertEquals(writer.status, 200)
    tests.assertEquals(writer.headers["Content-Type"], "text/html; charset=utf-8")
    tests.assertContains(writer.body, "Hello, World!")
    tests.assertContains(writer.body, "<!doctype html>")
end

local function greets_by_name()
    local writer = get(app(), "/api/hello", { name = "Ada" })
    tests.assertEquals(writer.status, 200)
    tests.assertEquals(json.decode(writer.body).message, "Hello, Ada!")
    tests.assertEquals(json.decode(get(app(), "/api/hello").body).message, "Hello, World!")
    tests.assertEquals(json.decode(get(app(), "/api/hello", { name = "" }).body).message, "Hello, World!")
end

local function rejects_invalid_names()
    local writer = get(app(), "/api/hello", { name = string.rep("x", 51) })
    tests.assertEquals(writer.status, 422)
    tests.assertContains(writer.body, '"code":"validation_failed"')
end

assert(tests.runSuite("Hello", {
    home_page_renders = home_page_renders,
    greets_by_name = greets_by_name,
    rejects_invalid_names = rejects_invalid_names,
}))
