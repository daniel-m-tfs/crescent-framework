#!/usr/bin/env lua
-- Crescent CLI: `lua cli.lua <command>` from the project root.
-- Generators, `new`, `setup`, `run`, `server` and `test` run on plain Lua; commands that need
-- OpenResty (database, routes) are re-run through bin/crescent, which uses
-- the `resty` CLI. Command modules are required lazily so plain Lua never
-- loads code that needs ngx.

package.path = "./?.lua;./?/init.lua;" .. package.path

local cli_output = require("crescent.utils.cli_output")
local colors = cli_output.colors

local args = {}
for index = 1, #arg do args[index] = arg[index] end
local command = table.remove(args, 1) or "help"

local HELP = {
    { "Project", {
        { "new <name>", "Create a new project in ./<name>" },
        { "setup", "Fresh git (+ optional remote), DB credentials, start Docker" },
        { "server [start|stop|reload|status]", "Control OpenResty (--conf file, --env name)" },
        { "routes", "List registered routes (METHOD, PATH, NAME)" },
    } },
    { "Development with Docker (app + MySQL, hot reload)", {
        { "run [--logs]", "Start the stack; Lua edits apply on the next request" },
        { "rerun [--logs] [--fresh]", "Rebuild the image (Dockerfile, deps, nginx) and restart" },
        { "stop", "Stop the stack (database and uploads are kept)" },
    } },
    { "Generators (never overwrite existing files)", {
        { "make:module <name>", "CRUD module: controller, service, model, routes, test, migration" },
        { "make:controller <name> [module]", "src/<module>/controllers/<name>.lua" },
        { "make:service <name> [module]", "src/<module>/services/<name>.lua" },
        { "make:model <name> [module]", "src/<module>/models/<name>.lua" },
        { "make:routes <name> [module]", "src/<module>/routes/<name>.lua" },
        { "make:job <name> [module]", "src/<module>/jobs/<name>.lua (background job)" },
        { "make:middleware <name> [module]", "src/middleware/<name>.lua (or inside a module)" },
        { "make:test <name>", "tests/test-<name>.lua" },
        { "make:migration <name>", "migrations/YYYYMMDDHHMMSS_<name>.lua" },
        { "make:seeder <name>", "seeds/<name>.lua (prefix with 01_ to order)" },
    } },
    { "Database (MySQL, reads .env)", {
        { "db:migrate", "Run pending migrations            (alias: migrate)" },
        { "db:rollback", "Roll back the last batch          (alias: migrate:rollback)" },
        { "db:status", "Show migration status             (alias: migrate:status)" },
        { "db:seed [name]", "Run seeders in seeds/ (or only <name>)" },
    } },
    { "Queues and cache (QUEUE_DRIVER/CACHE_DRIVER=redis)", {
        { "queue:work [--queue=a,b] [--once]", "Process jobs (--sleep, --max-jobs, --max-time, --stop-when-empty)" },
        { "queue:status [queue]", "Ready, delayed, reserved and failed counts" },
        { "queue:failed [queue]", "List failed jobs (--limit=20)" },
        { "queue:retry <id|all> [--queue=]", "Requeue failed jobs" },
        { "queue:clear-failed [queue]", "Delete failed jobs" },
        { "cache:clear", "Delete every key under the cache prefix" },
    } },
    { "Tests", {
        { "test [filter]", "Run tests/ on OpenResty LuaJIT (filter by file name)" },
        { "test:http", "Run tests/test-http.sh against a real OpenResty" },
        { "help", "Show this help" },
    } },
}

local EXAMPLES = {
    "lua cli.lua new my-api && cd my-api && lua cli.lua setup",
    "lua cli.lua run --logs",
    "lua cli.lua make:module Product",
    "lua cli.lua make:controller Report shop",
    "lua cli.lua make:migration add_price_to_products",
    "lua cli.lua make:job send_welcome users",
    "lua cli.lua db:migrate",
    "lua cli.lua test products",
}

local function show_help()
    cli_output.print_header("Crescent CLI")
    print("Usage: lua cli.lua <command> [arguments]   (or ./bin/crescent <command>)")
    for _, section in ipairs(HELP) do
        print("\n" .. colors.bold .. section[1] .. colors.reset)
        for _, entry in ipairs(section[2]) do
            print(string.format("  %s%-34s%s %s", colors.green, entry[1], colors.reset, entry[2]))
        end
    end
    print("\n" .. colors.bold .. "Examples" .. colors.reset)
    for _, example in ipairs(EXAMPLES) do print("  " .. colors.dim .. example .. colors.reset) end
    print("")
end

local function require_name(value, usage)
    if value == nil or value == "" then
        cli_output.print_error("missing argument. Usage: lua cli.lua " .. usage)
        return false
    end
    return true
end

local function make(kind, usage)
    return function()
        if not require_name(args[1], usage) then return false end
        return require("cli.commands.make")[kind](args[1], args[2])
    end
end

-- Database commands live in cli/commands/db.lua; the result convention is
-- `false` or `nil, err` for failure.
local function db(operation)
    return function()
        local module = require("cli.commands.db")
        local result, err = module[operation]({ name = args[1] })
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
    setup = function() return require("cli.commands.setup").run() end,
    run = function() return require("cli.commands.docker").run_command(args) end,
    rerun = function() return require("cli.commands.docker").rerun_command(args) end,
    stop = function() return require("cli.commands.docker").stop() end,
    server = function() return require("cli.commands.server").run(args) end,
    routes = function() return require("cli.commands.routes").run() end,
    ["make:module"] = function()
        if not require_name(args[1], "make:module <name>") then return false end
        return require("cli.commands.make").module(args[1])
    end,
    ["make:controller"] = make("controller", "make:controller <name> [module]"),
    ["make:service"] = make("service", "make:service <name> [module]"),
    ["make:model"] = make("model", "make:model <name> [module]"),
    ["make:routes"] = make("routes", "make:routes <name> [module]"),
    ["make:job"] = make("job", "make:job <name> [module]"),
    ["make:middleware"] = make("middleware", "make:middleware <name> [module]"),
    ["make:test"] = make("test", "make:test <name>"),
    ["make:migration"] = make("migration", "make:migration <name>"),
    ["make:seeder"] = function()
        if not require_name(args[1], "make:seeder <name>") then return false end
        return require("cli.commands.db").make_seeder(args[1]) ~= false
    end,
    ["db:migrate"] = db("migrate"),
    ["db:rollback"] = db("rollback"),
    ["db:status"] = db("status"),
    ["db:seed"] = db("seed"),
    ["queue:work"] = function() return require("cli.commands.queue").work(args) end,
    ["queue:status"] = function() return require("cli.commands.queue").status(args) end,
    ["queue:failed"] = function() return require("cli.commands.queue").failed(args) end,
    ["queue:retry"] = function() return require("cli.commands.queue").retry(args) end,
    ["queue:clear-failed"] = function() return require("cli.commands.queue").clear_failed(args) end,
    ["cache:clear"] = function() return require("cli.commands.queue").cache_clear() end,
}
COMMANDS.migrate = COMMANDS["db:migrate"]
COMMANDS["migrate:rollback"] = COMMANDS["db:rollback"]
COMMANDS["migrate:status"] = COMMANDS["db:status"]
COMMANDS["--help"] = COMMANDS.help
COMMANDS["-h"] = COMMANDS.help
-- Crescent 2.0.0 called controllers "actions".
COMMANDS["make:action"] = function()
    cli_output.print_warning("make:action is now make:controller")
    return COMMANDS["make:controller"]()
end

-- Commands that need cosockets or the full framework (which uses ngx).
local NEEDS_OPENRESTY = {
    routes = true, ["db:migrate"] = true, ["db:rollback"] = true, ["db:status"] = true, ["db:seed"] = true,
    migrate = true, ["migrate:rollback"] = true, ["migrate:status"] = true,
    ["queue:work"] = true, ["queue:status"] = true, ["queue:failed"] = true, ["queue:retry"] = true,
    ["queue:clear-failed"] = true, ["cache:clear"] = true,
}

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Re-runs this command through bin/crescent (resty) and returns its status.
local function delegate()
    local file = io.open("bin/crescent", "r")
    if not file then
        cli_output.print_error("'" .. command .. "' needs OpenResty and bin/crescent was not found; run it from the project root")
        return false
    end
    file:close()
    local parts = { "./bin/crescent", shell_quote(command) }
    for _, value in ipairs(args) do parts[#parts + 1] = shell_quote(value) end
    local env = cli_output.is_enabled() and "CRESCENT_COLOR=1 " or ""
    local first, _, code = os.execute(env .. table.concat(parts, " "))
    if type(first) == "number" then return first == 0 end
    return first == true and (code == nil or code == 0)
end

local handler = COMMANDS[command]
if not handler then
    cli_output.print_error("Unknown command: " .. tostring(command))
    show_help()
    os.exit(2)
end
if NEEDS_OPENRESTY[command] and not ngx then handler = delegate end
if not handler() then os.exit(1) end
