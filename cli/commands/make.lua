-- make:* generators. Every name is validated before any path is built and
-- existing files are never overwritten.
local cli_output = require("crescent.utils.cli_output")
local fs = require("cli.fs")
local Templates = require("cli.templates")

local Make = {}

-- Base directory for generated files; tests point it at a temp directory.
Make.root = "."

local function invalid_name(label, value)
    cli_output.print_error(string.format(
        "Invalid %s '%s': use letters, digits, '_' or '-', starting with a letter (max 64).",
        label, tostring(value)))
    return false
end

local function check_names(name, module_name)
    if not Templates.is_valid_name(name) then return invalid_name("name", name) end
    if module_name ~= nil and not Templates.is_valid_name(module_name) then
        return invalid_name("module name", module_name)
    end
    return true
end

local function path(relative)
    return fs.join(Make.root, relative)
end

local function write(relative, content)
    local ok, err = fs.write_new(path(relative), content)
    if ok then
        print("  created " .. relative)
        return true
    end
    cli_output.print_error(tostring(err))
    return false
end

local function generate(kind, directory, name, module_name)
    if not check_names(name, module_name) then return false end
    local vars = Templates.vars(name, module_name)
    local relative = string.format("src/%s/%s/%s.lua", vars.module, directory, vars.name)
    return write(relative, Templates.render(Templates[kind], vars))
end

function Make.action(name, module_name) return generate("action", "actions", name, module_name) end
function Make.service(name, module_name) return generate("service", "services", name, module_name) end
function Make.model(name, module_name) return generate("model", "models", name, module_name) end
function Make.routes(name, module_name) return generate("routes", "routes", name, module_name) end

-- Without a module the middleware goes to src/middleware/<name>.lua.
function Make.middleware(name, module_name)
    if not check_names(name, module_name) then return false end
    local vars = Templates.vars(name, module_name)
    local directory = module_name and ("src/" .. vars.module .. "/middleware") or "src/middleware"
    vars.require_path = (directory .. "/" .. vars.name):gsub("/", ".")
    return write(directory .. "/" .. vars.name .. ".lua", Templates.render(Templates.middleware, vars))
end

function Make.test(name)
    if not check_names(name) then return false end
    local vars = Templates.vars(name)
    return write("tests/test-" .. vars.name:gsub("_", "-") .. ".lua", Templates.render(Templates.test, vars))
end

function Make.module(name)
    if not check_names(name) then return false end
    local vars = Templates.vars(name)
    local base = "src/" .. vars.module
    local files = {
        { base .. "/init.lua", Templates.module_init },
        { base .. "/models/" .. vars.name .. ".lua", Templates.model },
        { base .. "/services/" .. vars.name .. ".lua", Templates.module_service },
        { base .. "/actions/" .. vars.name .. ".lua", Templates.module_action },
        { base .. "/routes/" .. vars.name .. ".lua", Templates.module_routes },
        { "tests/test-" .. vars.module:gsub("_", "-") .. "-module.lua", Templates.module_test },
    }
    -- All or nothing: refuse before writing anything if a file exists.
    for _, file in ipairs(files) do
        if fs.exists(path(file[1])) then
            cli_output.print_error("file already exists: " .. file[1])
            return false
        end
    end

    cli_output.print_header("Creating module " .. vars.Name)
    for _, file in ipairs(files) do
        if not write(file[1], Templates.render(file[2], vars)) then return false end
    end
    local migration = Make.migration_file("create_" .. vars.plural .. "_table")
    if not migration then return false end
    cli_output.print_info("Register it in app.lua and create the table:")
    print(string.format('  require("src.%s").register(app)', vars.module))
    print("  bin/crescent db:migrate      # " .. migration)
    return true
end

function Make.migration_file(name, timestamp)
    timestamp = timestamp or os.date("%Y%m%d%H%M%S")
    local relative = string.format("migrations/%s_%s.lua", timestamp, name)
    local content = Templates.render(Templates.migration, {
        migration = name,
        table = Templates.migration_table(name),
    })
    if not write(relative, content) then return nil end
    return relative
end

-- Prefers cli.commands.db.make_migration so migrations have a single owner;
-- falls back to writing the file in the same format.
function Make.migration(name)
    if not check_names(name) then return false end
    local loaded, db = pcall(require, "cli.commands.db")
    if loaded and type(db) == "table" and type(db.make_migration) == "function" and Make.root == "." then
        local result, err = db.make_migration(name)
        if result == false or (result == nil and err) then
            cli_output.print_error(tostring(err or "unable to create migration"))
            return false
        end
        return true
    end
    return Make.migration_file(name) ~= nil
end

return Make
