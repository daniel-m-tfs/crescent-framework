#!/usr/bin/env lua
-- Crescent CLI. Run it on OpenResty with `./bin/crescent <command>`; `test`
-- and `help` also work on plain Lua (`lua cli.lua test`). Command modules are
-- required lazily so plain Lua never loads code that needs ngx.

package.path = "./?.lua;./?/init.lua;" .. package.path

local cli_output = require("crescent.utils.cli_output")

local args = {}
for index = 1, #arg do args[index] = arg[index] end
local command = table.remove(args, 1) or "help"

local HELP = [[
Usage: ./bin/crescent <command> [arguments]   (or: lua cli.lua test|help)

Project
  new <name>                    Create a new project in ./<name>
  server [start|stop|reload|status] [--conf file] [--env name]
                                Control OpenResty for this project
  routes                        List registered routes (METHOD, PATH, NAME)

Generators (never overwrite existing files)
  make:module <name>            CRUD module: model, service, actions, routes, init, test
  make:action <name> [module]   src/<module>/actions/<name>.lua
  make:service <name> [module]  src/<module>/services/<name>.lua
  make:model <name> [module]    src/<module>/models/<name>.lua
  make:routes <name> [module]   src/<module>/routes/<name>.lua
  make:middleware <name> [module]
                                src/middleware/<name>.lua (or inside a module)
  make:test <name>              tests/test-<name>.lua
  make:migration <name>         migrations/YYYYMMDDHHMMSS_<name>.lua

Database (MySQL)
  db:migrate     (alias: migrate)            Run pending migrations
  db:rollback    (alias: migrate:rollback)   Roll back the last migration
  db:status      (alias: migrate:status)     Show migration status
  db:seed [name]                             Run seeders in seeds/ (or only <name>)
  make:seeder <name>                         seeds/<name>.lua

Tests
  test [filter]                 Run tests/ on OpenResty LuaJIT
  test:http                     Run HTTP integration tests against OpenResty
  help                          Show this help
]]

local function show_help()
    cli_output.print_header("Crescent CLI")
    print(HELP)
end

local function require_name(value, usage)
    if value == nil or value == "" then
        cli_output.print_error("missing argument. Usage: " .. usage)
        return false
    end
    return true
end

local function make(kind)
    return function()
        local name, module_name = args[1], args[2]
        if not require_name(name, "make:" .. kind .. " <name>") then return false end
        return require("cli.commands.make")[kind](name, module_name)
    end
end

-- Database commands live in cli/commands/db.lua; the result convention is
-- `false` or `nil, err` for failure.
local function db(operation)
    return function()
        local loaded, module = pcall(require, "cli.commands.db")
        if not loaded then
            if tostring(module):find("module 'cli.commands.db' not found", 1, true) then
                cli_output.print_error("database commands are not available (cli/commands/db.lua is missing)")
            else
                cli_output.print_error("unable to load database commands: " .. tostring(module))
            end
            return false
        end
        if type(module[operation]) ~= "function" then
            cli_output.print_error("cli.commands.db does not implement " .. operation .. "()")
            return false
        end
        local result, err = module[operation]()
        if result == false or (result == nil and err ~= nil) then
            if err ~= nil then cli_output.print_error(tostring(err)) end
            return false
        end
        return true
    end
end

local COMMANDS = {
    help = function() show_help() return true end,
    test = function() return require("cli.commands.test").run(args[1]) end,
    ["test:http"] = function() return require("cli.commands.test").run_http() end,
    new = function() return require("cli.commands.new").run(args[1]) end,
    server = function() return require("cli.commands.server").run(args) end,
    routes = function() return require("cli.commands.routes").run() end,
    ["make:module"] = function()
        if not require_name(args[1], "make:module <name>") then return false end
        return require("cli.commands.make").module(args[1])
    end,
    ["make:action"] = make("action"),
    ["make:service"] = make("service"),
    ["make:model"] = make("model"),
    ["make:routes"] = make("routes"),
    ["make:middleware"] = make("middleware"),
    ["make:test"] = make("test"),
    ["make:migration"] = make("migration"),
    ["db:migrate"] = db("migrate"),
    ["db:rollback"] = db("rollback"),
    ["db:status"] = db("status"),
    ["db:seed"] = function() return require("cli.commands.db").seed({ name = args[1] }) end,
    ["make:seeder"] = function()
        if not require_name(args[1], "make:seeder <name>") then return false end
        return require("cli.commands.db").make_seeder(args[1]) ~= false
    end,
}
COMMANDS.migrate = COMMANDS["db:migrate"]
COMMANDS["migrate:rollback"] = COMMANDS["db:rollback"]
COMMANDS["migrate:status"] = COMMANDS["db:status"]
COMMANDS["--help"] = COMMANDS.help
COMMANDS["-h"] = COMMANDS.help

local handler = COMMANDS[command]
if not handler then
    cli_output.print_error("Unknown command: " .. tostring(command))
    show_help()
    os.exit(2)
end
if not handler() then os.exit(1) end
