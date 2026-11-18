-- make:* generators. Every name is validated before any path is built and
-- existing files are never overwritten.
--
-- Module layout (same as Crescent 1.x):
--   src/<module>/init.lua                  Module.register(app)
--   src/<module>/controllers/<name>.lua    receive ctx, call services, respond
--   src/<module>/services/<name>.lua       business logic (no ctx)
--   src/<module>/models/<name>.lua         Model:extend({...})
--   src/<module>/routes/<name>.lua         function(app, prefix)
--   src/<module>/jobs/<name>.lua           background job (crescent.queue)
local cli_output = require("crescent.utils.cli_output")
local fs = require("cli.fs")
local Templates = require("cli.templates")

local Make = {}

-- Base directory for generated files; tests point it at a temp directory.
Make.root = "."

local LABELS = {
    controller = "Controller",
    service = "Service",
    job = "Job",
    model = "Model",
    routes = "Routes",
    middleware = "Middleware",
    test = "Test",
    migration = "Migration",
    module = "Module",
}

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

local function write(kind, relative, content)
    local ok, err = fs.write_new(path(relative), content)
    if ok then
        cli_output.print_success(string.format("%-11s %s", LABELS[kind], relative))
        return true
    end
    cli_output.print_error(tostring(err))
    return false
end

local function generate(kind, directory, name, module_name)
    if not check_names(name, module_name) then return false end
    local vars = Templates.vars(name, module_name)
    local relative = string.format("src/%s/%s/%s.lua", vars.module, directory, vars.name)
    return write(kind, relative, Templates.render(Templates[kind], vars))
end

function Make.controller(name, module_name) return generate("controller", "controllers", name, module_name) end
function Make.service(name, module_name) return generate("service", "services", name, module_name) end
function Make.model(name, module_name) return generate("model", "models", name, module_name) end
function Make.routes(name, module_name) return generate("routes", "routes", name, module_name) end

function Make.job(name, module_name)
    if not generate("job", "jobs", name, module_name) then return false end
    local vars = Templates.vars(name, module_name)
    cli_output.print_info("Push it with:")
    cli_output.print_code(string.format('ctx.queue:push("src.%s.jobs.%s", { --[[ payload ]] })', vars.module, vars.name))
    return true
end

-- Without a module the middleware goes to src/middleware/<name>.lua.
function Make.middleware(name, module_name)
    if not check_names(name, module_name) then return false end
    local vars = Templates.vars(name, module_name)
    local directory = module_name and ("src/" .. vars.module .. "/middleware") or "src/middleware"
    vars.require_path = (directory .. "/" .. vars.name):gsub("/", ".")
    if not write("middleware", directory .. "/" .. vars.name .. ".lua", Templates.render(Templates.middleware, vars)) then
        return false
    end
    cli_output.print_info("Register it in app.lua:")
    cli_output.print_code(string.format('app:use(require("%s"))', vars.require_path))
    return true
end

function Make.test(name)
    if not check_names(name) then return false end
    local vars = Templates.vars(name)
    local relative = "tests/test-" .. vars.name:gsub("_", "-") .. ".lua"
    if not write("test", relative, Templates.render(Templates.test, vars)) then return false end
    cli_output.print_info("Run it with: lua cli.lua test " .. vars.name:gsub("_", "-"))
    return true
end

function Make.module(name)
    if not check_names(name) then return false end
    local vars = Templates.vars(name)
    local base = "src/" .. vars.module
    local files = {
        { "module", base .. "/init.lua", Templates.module_init },
        { "controller", base .. "/controllers/" .. vars.name .. ".lua", Templates.module_controller },
        { "service", base .. "/services/" .. vars.name .. ".lua", Templates.module_service },
        { "model", base .. "/models/" .. vars.name .. ".lua", Templates.model },
        { "routes", base .. "/routes/" .. vars.name .. ".lua", Templates.module_routes },
        { "test", "tests/test-" .. vars.module:gsub("_", "-") .. "-module.lua", Templates.module_test },
    }
    -- All or nothing: refuse before writing anything if a file exists.
    for _, file in ipairs(files) do
        if fs.exists(path(file[2])) then
            cli_output.print_error("file already exists: " .. file[2])
            return false
        end
    end

    cli_output.print_header("Creating module " .. vars.Name)
    for _, file in ipairs(files) do
        if not write(file[1], file[2], Templates.render(file[3], vars)) then return false end
    end
    local migration = Make.migration_file("create_" .. vars.plural .. "_table")
    if not migration then return false end

    print("")
    cli_output.print_info("Register the module in app.lua:")
    cli_output.print_code(string.format('require("src.%s").register(app)', vars.module))
    cli_output.print_info("Then create the table and run the module test:")
    cli_output.print_code("lua cli.lua db:migrate\nlua cli.lua test " .. vars.module:gsub("_", "-"))
    print("")
    print(string.format("  Routes: GET|POST /%s   GET|PUT|DELETE /%s/{id}", vars.plural, vars.plural))
    return true
end

-- Writes migrations/<timestamp>_<name>.lua; returns the relative path or nil.
function Make.migration_file(name, timestamp)
    timestamp = timestamp or os.date("%Y%m%d%H%M%S")
    local relative = string.format("migrations/%s_%s.lua", timestamp, name)
    if not write("migration", relative, Templates.migration_for(name)) then return nil end
    return relative
end

function Make.migration(name)
    if not check_names(name) then return false end
    if not Make.migration_file(name) then return false end
    cli_output.print_info("Edit up()/down(), then run: lua cli.lua db:migrate")
    return true
end

return Make
