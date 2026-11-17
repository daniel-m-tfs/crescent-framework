package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local fs = require("cli.fs")
local New = require("cli.commands.new")
local Server = require("cli.commands.server")
local Routes = require("cli.commands.routes")
local Crescent = require("crescent")

local function temp_dir()
    local handle = io.popen("mktemp -d")
    local path = handle:read("*l")
    handle:close()
    return path
end

local function quietly(callback, ...)
    local original = print
    print = function() end
    local ok, result = pcall(callback, ...)
    print = original
    if not ok then error(result, 0) end
    return result
end

local function new_scaffolds_project()
    local parent = temp_dir()
    local ok, err = pcall(function()
        tests.assertTrue(quietly(New.run, "my-app", { source = ".", parent = parent }))
        local root = fs.join(parent, "my-app")
        for _, relative in ipairs({
            "app.lua", "nginx.conf", "conf/nginx.production.conf", "config/development.lua",
            "config/production.lua", "config/test.lua", ".env.example", ".gitignore", "deps.sh",
            "src/health/init.lua", "src/hello/init.lua", "src/hello/controllers/hello.lua",
            "views/layout.etlua", "views/hello/index.etlua", "public/css/app.css",
            "migrations/.gitkeep", "seeds/.gitkeep", "tests/test-health.lua", "tests/test-hello.lua",
            "Dockerfile", "docker-compose.yml", ".dockerignore", "docker/entrypoint.sh",
            "docker/mysql-init/01-test-database.sh", "conf/nginx.docker.conf", "conf/nginx.docker-dev.conf", "crescent/application.lua", "crescent/utils/tests.lua",
            "cli/commands/make.lua", "cli/templates/project/app.lua", "cli.lua", "bin/crescent",
            "logs/.gitkeep", "tmp/.gitkeep", "storage/.gitkeep", "tests/test-http.sh", ".env", "llm.md",
        }) do
            tests.assertTrue(fs.exists(fs.join(root, relative)), "missing " .. relative)
        end
        for _, relative in ipairs(fs.list_files(root)) do
            if relative:match("%.lua$") then
                tests.assertNotNil(loadfile(fs.join(root, relative)), "does not compile: " .. relative)
            end
            if not relative:match("^cli/templates/") then
                tests.assertNotContains(fs.read(fs.join(root, relative)), "{{project}}", relative)
                tests.assertNotContains(fs.read(fs.join(root, relative)), "{{db_name}}", relative)
            end
        end
        tests.assertContains(fs.read(fs.join(root, "config/development.lua")), '"my_app_dev"')
        tests.assertContains(fs.read(fs.join(root, "src/health/init.lua")), '"my-app"')
        tests.assertContains(fs.read(fs.join(root, "llm.md")), "# my-app — guide for AI models")
        tests.assertTrue(fs.execute("test -x " .. fs.shell_quote(fs.join(root, "docker/entrypoint.sh"))))
        tests.assertTrue(fs.execute("test -x " .. fs.shell_quote(fs.join(root, "bin/crescent"))))
        tests.assertTrue(fs.execute("test -x " .. fs.shell_quote(fs.join(root, "deps.sh"))))
        tests.assertTrue(fs.execute("test -x " .. fs.shell_quote(fs.join(root, "tests/test-http.sh"))))
        local env = fs.read(fs.join(root, ".env"))
        local app_key, jwt_secret = env:match("\nAPP_KEY=(%x+)\n"), env:match("\nJWT_SECRET=(%x+)\n")
        tests.assertEquals(#(app_key or ""), 96, ".env gets a random APP_KEY")
        tests.assertEquals(#(jwt_secret or ""), 96, ".env gets a random JWT_SECRET")
        tests.assertNotEquals(app_key, jwt_secret)
        tests.assertContains(fs.read(fs.join(root, ".env.example")), "\nAPP_KEY=\n", ".env.example keeps secrets empty")

        tests.assertFalse(quietly(New.run, "my-app", { source = ".", parent = parent }), "existing directory")
        for _, name in ipairs({ "../x", "a;rm -rf", "$(x)", "a b", "", "x/y" }) do
            tests.assertFalse(quietly(New.run, name, { source = ".", parent = parent }), "accepted " .. name)
        end
        tests.assertFalse(quietly(New.run, nil, { source = ".", parent = parent }))
        local handle = io.popen("ls -A " .. fs.shell_quote(parent))
        local entries = handle:read("*a")
        handle:close()
        tests.assertEquals(entries, "my-app\n", "invalid names must not create anything")
    end)
    fs.execute("rm -rf " .. fs.shell_quote(parent))
    if not ok then error(err, 0) end
end

local function server_arguments()
    local options = Server.parse({})
    tests.assertEquals(options.action, "start")
    tests.assertEquals(options.conf, "nginx.conf")
    options = Server.parse({ "reload", "--conf", "conf/nginx.production.conf", "--env", "production" })
    tests.assertEquals(options.action, "reload")
    tests.assertEquals(options.conf, "conf/nginx.production.conf")

    local command = Server.command(options, "/srv/my app")
    tests.assertContains(command, "APP_ENV='production' ")
    tests.assertContains(command, " -p '/srv/my app/'")
    tests.assertContains(command, " -c 'conf/nginx.production.conf'")
    tests.assertContains(command, " -s reload")
    tests.assertContains(Server.command(Server.parse({ "stop" }), "/srv"), " -s quit")
    tests.assertNotContains(Server.command(Server.parse({ "start" }), "/srv"), " -s ")

    tests.assertNil(Server.parse({ "--env", "prod;rm -rf /" }))
    tests.assertNil(Server.parse({ "--conf" }))
    tests.assertNil(Server.parse({ "restart" }))
    tests.assertNil(Server.parse({ "start", "stop" }))
    tests.assertFalse(quietly(Server.run, { "status", "--conf", "missing.conf" }))
end

local function routes_table()
    local app = Crescent.new({ environment = "test", debug = true })
    local action = function(ctx) return ctx:no_content() end
    app:get("/users/{id}", action, "users.show")
    app:get("/users", action, "users.index")
    app:post("/users", action)
    local rows = Routes.collect(app)
    tests.assertEquals(#rows, 3)
    tests.assertEquals(rows[1].path, "/users")
    tests.assertEquals(rows[1].method, "GET")
    tests.assertEquals(rows[2].method, "POST")
    tests.assertEquals(rows[3].name, "users.show")
    local output = Routes.format(rows)
    tests.assertContains(output, "METHOD  PATH         NAME")
    tests.assertContains(output, "GET     /users/{id}  users.show")
end

assert(tests.runSuite("CLI commands", {
    new_scaffolds_project = new_scaffolds_project,
    server_arguments = server_arguments,
    routes_table = routes_table,
}))
