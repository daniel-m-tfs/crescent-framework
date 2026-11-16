-- `new <name>`: scaffolds a project from cli/templates/project plus a copy of
-- the framework and its runtime files (crescent/, cli/, cli.lua, bin/crescent,
-- nginx/Docker configuration, deps.sh). Runtime files are copied from the
-- framework root — never duplicated in the templates — so new projects always
-- get the current configuration. No network access.
local cli_output = require("crescent.utils.cli_output")
local fs = require("cli.fs")
local Templates = require("cli.templates")

local New = {}

local FRAMEWORK_DIRS = { "crescent", "cli", "conf", "docker" }
local FRAMEWORK_FILES = {
    "cli.lua", "bin/crescent", "nginx.conf", "deps.sh",
    "Dockerfile", "docker-compose.yml", ".dockerignore",
}
local EXECUTABLES = {
    "bin/crescent", "deps.sh", "test.sh", "docker/entrypoint.sh", "docker/mysql-init/01-test-database.sh",
}

-- Template files named `dot-x` become `.x`, so the template tree never
-- carries a live .gitignore/.env into this repository.
local function target_name(relative)
    return (relative:gsub("^dot%-", "."):gsub("/dot%-", "/."))
end

local function copy(source, destination, vars)
    local content, err = fs.read(source)
    if not content then return nil, err end
    if vars then content = Templates.render(content, vars) end
    return fs.write_new(destination, content)
end

local function scaffold(source_root, target, vars)
    local template_root = fs.join(source_root, "cli/templates/project")
    if not fs.is_dir(template_root) then return nil, "project templates not found in " .. template_root end
    for _, relative in ipairs(fs.list_files(template_root)) do
        local ok, err = copy(fs.join(template_root, relative), fs.join(target, target_name(relative)), vars)
        if not ok then return nil, err end
    end
    for _, directory in ipairs(FRAMEWORK_DIRS) do
        local root = fs.join(source_root, directory)
        for _, relative in ipairs(fs.list_files(root)) do
            local ok, err = copy(fs.join(root, relative), fs.join(target, directory, relative))
            if not ok then return nil, err end
        end
    end
    for _, relative in ipairs(FRAMEWORK_FILES) do
        local ok, err = copy(fs.join(source_root, relative), fs.join(target, relative))
        if not ok then return nil, err end
    end
    for _, relative in ipairs(EXECUTABLES) do fs.chmod_executable(fs.join(target, relative)) end
    return true
end

-- options.source: framework root to copy from (default CRESCENT_HOME or cwd);
-- options.parent: directory that receives the project (default CRESCENT_CWD,
-- set by bin/crescent to the caller's directory, or cwd).
function New.run(name, options)
    options = options or {}
    if name == nil or name == "" then
        cli_output.print_error("Project name is required. Usage: crescent new <name>")
        return false
    end
    if not Templates.is_valid_name(name) then
        cli_output.print_error("Invalid project name '" .. tostring(name)
            .. "': use letters, digits, '_' or '-', starting with a letter (max 64).")
        return false
    end

    local source = options.source or os.getenv("CRESCENT_HOME") or "."
    local parent = options.parent or os.getenv("CRESCENT_CWD") or "."
    local target = fs.join(parent, name)
    if fs.exists(target) then
        cli_output.print_error("'" .. target .. "' already exists")
        return false
    end

    cli_output.print_header("Creating Crescent project " .. name)
    local vars = { project = name, db_name = Templates.snake(name) }
    local ok, err = scaffold(source, target, vars)
    if not ok then
        cli_output.print_error("Unable to create project: " .. tostring(err))
        fs.execute("rm -rf " .. fs.shell_quote(target))
        return false
    end

    print("Project created in " .. target)
    cli_output.print_info("Next steps:")
    print("  cd " .. name)
    print("  cp .env.example .env")
    print("  docker compose up --build    # app + MySQL on http://127.0.0.1:8080")
    print("or without Docker (OpenResty installed locally):")
    print("  ./deps.sh && ./bin/crescent server start")
    return true
end

return New
