-- Database commands. migrate/rollback/status need OpenResty cosockets, so
-- they must run under the `resty` CLI:
--   resty -I lua_modules/share/lua/5.1 cli/commands/db.lua migrate
-- make_migration only touches the filesystem and works under plain Lua.
local is_script = arg and type(arg[0]) == "string" and arg[0]:match("cli/commands/db%.lua$") ~= nil
if is_script then package.path = "./?.lua;./?/init.lua;" .. package.path end

local cli_output = require("crescent.utils.cli_output")

local DbCommand = {}

local function database(options)
    options = options or {}
    if options.adapter then return options.adapter end
    local Database = require("crescent.database")
    if not Database.is_configured() then
        local config = require("crescent.config").load(options.environment)
        if type(config.database) ~= "table" then error("config.database is missing", 0) end
        Database.configure(config.database)
    end
    return Database.default()
end

local function migrator(options)
    options = options or {}
    local Migrator = require("crescent.database.migration")
    return Migrator.new(database(options), {
        path = options.path,
        table = options.table,
        log = function(event, name)
            if event == "migrating" then print("  → migrating " .. name)
            elseif event == "rolling_back" then print("  ← rolling back " .. name) end
        end,
    })
end

local function guarded(fn)
    return function(options)
        local ok, result = pcall(fn, options)
        if ok then return result end
        cli_output.print_error(tostring(result))
        return false
    end
end

DbCommand.migrate = guarded(function(options)
    cli_output.print_header("Database migrations")
    local result, err, info = migrator(options):migrate()
    if not result then
        cli_output.print_error(tostring(err))
        if info and #(info.migrated or {}) > 0 then
            print("Applied before the failure: " .. table.concat(info.migrated, ", "))
        end
        return false
    end
    if #result.migrated == 0 then
        cli_output.print_info("Nothing to migrate")
    else
        cli_output.print_success(string.format("Batch %d: %d migration(s) applied", result.batch, #result.migrated))
    end
    return true
end)

DbCommand.rollback = guarded(function(options)
    cli_output.print_header("Database rollback")
    local result, err, info = migrator(options):rollback()
    if not result then
        cli_output.print_error(tostring(err))
        if info and #(info.rolled_back or {}) > 0 then
            print("Reverted before the failure: " .. table.concat(info.rolled_back, ", "))
        end
        return false
    end
    if #result.rolled_back == 0 then
        cli_output.print_info("Nothing to roll back")
    else
        cli_output.print_success(string.format("Batch %d: %d migration(s) reverted", result.batch, #result.rolled_back))
    end
    return true
end)

DbCommand.status = guarded(function(options)
    cli_output.print_header("Migration status")
    local rows, err = migrator(options):status()
    if not rows then
        cli_output.print_error(tostring(err))
        return false
    end
    if #rows == 0 then
        cli_output.print_info("No migrations found")
        return true
    end
    local colors = cli_output.colors
    local STATUS_COLOR = { ran = "green", pending = "yellow", missing = "red" }
    print(colors.bold .. string.format("  %-50s %-8s %s", "Migration", "Status", "Batch") .. colors.reset)
    local pending = 0
    for _, row in ipairs(rows) do
        local status = row.missing and "missing" or (row.ran and "ran" or "pending")
        if status == "pending" then pending = pending + 1 end
        print(string.format("  %-50s %s %s", row.name,
            cli_output.paint(STATUS_COLOR[status], string.format("%-8s", status)),
            row.batch and tostring(row.batch) or ""))
    end
    print("")
    if pending > 0 then
        cli_output.print_info(pending .. " pending migration(s): run db:migrate")
    else
        cli_output.print_success("Database is up to date")
    end
    return true
end)

DbCommand.seed = guarded(function(options)
    options = options or {}
    cli_output.print_header("Database seeders")
    local Seeder = require("crescent.database.seeder")
    local seeder = Seeder.new(database(options), {
        path = options.seeds_path,
        log = function(_, name) print("  → seeding " .. name) end,
    })
    local result, err = seeder:run(options.name)
    if not result then
        cli_output.print_error(tostring(err))
        return false
    end
    if #result.seeded == 0 then
        cli_output.print_info("No seeders found in " .. (options.seeds_path or "seeds") .. "/")
    else
        cli_output.print_success(string.format("%d seeder(s) applied", #result.seeded))
    end
    return true
end)

local SEEDER_TEMPLATE = [[
-- Seeder %s. Runs inside a transaction; return false (or raise) to roll back.
-- Seeders are not recorded: keep them idempotent if they may run again.
return function(db)
    -- local User = require("src.users.models.user")
    -- if not User:where("email", "admin@example.com"):first(db) then
    --     assert(User:create({ name = "Admin", email = "admin@example.com" }, db))
    -- end
end
]]

-- Writes seeds/<name>.lua. Returns the path or false.
function DbCommand.make_seeder(name, options)
    options = options or {}
    -- A numeric prefix (01_admin_user) controls the order seeders run in.
    if type(name) ~= "string" or #name > 64 or not name:match("^[%w][%w_]*$") then
        cli_output.print_error("seeder name must match ^[A-Za-z0-9][A-Za-z0-9_]*$ (e.g. 01_admin_user)")
        return false
    end
    local directory = options.path or "seeds"
    local path = directory .. "/" .. name .. ".lua"
    local existing = io.open(path, "r")
    if existing then
        existing:close()
        cli_output.print_error("seeder already exists: " .. path)
        return false
    end
    os.execute("mkdir -p '" .. directory:gsub("'", "'\\''") .. "'")
    local file, err = io.open(path, "w")
    if not file then
        cli_output.print_error("unable to write " .. path .. ": " .. tostring(err))
        return false
    end
    file:write(string.format(SEEDER_TEMPLATE, name))
    file:close()
    cli_output.print_success("Seeder      " .. path)
    cli_output.print_info("Run it with: lua cli.lua db:seed " .. name)
    return path
end

-- Writes migrations/YYYYMMDDHHMMSS_<name>.lua. Returns the path or false.
function DbCommand.make_migration(name, options)
    options = options or {}
    if type(name) ~= "string" or not name:match("^[%a][%w_]*$") then
        cli_output.print_error("migration name must match ^[A-Za-z][A-Za-z0-9_]*$")
        return false
    end
    local directory = options.path or "migrations"
    local stamp = options.timestamp or os.date("%Y%m%d%H%M%S")
    local file_name = stamp .. "_" .. name
    local path = directory .. "/" .. file_name .. ".lua"

    local existing = io.open(path, "r")
    if existing then
        existing:close()
        cli_output.print_error("migration already exists: " .. path)
        return false
    end
    os.execute("mkdir -p '" .. directory:gsub("'", "'\\''") .. "'")
    local file, err = io.open(path, "w")
    if not file then
        cli_output.print_error("unable to write " .. path .. ": " .. tostring(err))
        return false
    end
    file:write(require("cli.templates").migration_for(name))
    file:close()
    cli_output.print_success("Migration   " .. path)
    return path
end

local COMMANDS = {
    migrate = DbCommand.migrate,
    rollback = DbCommand.rollback,
    status = DbCommand.status,
}

-- run("migrate") / run("make_migration", "create_users")
function DbCommand.run(command, argument)
    if command == "make_migration" or command == "make:migration" then
        return DbCommand.make_migration(argument) ~= false
    end
    if command == "make_seeder" or command == "make:seeder" then
        return DbCommand.make_seeder(argument) ~= false
    end
    if command == "seed" then
        return DbCommand.seed({ name = argument })
    end
    local handler = COMMANDS[command]
    if not handler then
        cli_output.print_error("unknown db command: " .. tostring(command))
        return false
    end
    return handler()
end

-- Executed directly as a script (e.g. by `resty cli/commands/db.lua migrate`).
if is_script then
    os.exit(DbCommand.run(arg[1], arg[2]) and 0 or 1)
end

return DbCommand
