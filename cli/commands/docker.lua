-- `run`, `rerun` and `stop`: the Docker development stack (docker-compose.yml:
-- app with the source mounted and lua_code_cache off, plus MySQL). Edits to
-- Lua files apply on the next request; `rerun` rebuilds the image for changes
-- to the Dockerfile, dependencies or nginx configuration.
local cli_output = require("crescent.utils.cli_output")
local fs = require("cli.fs")
local EnvFile = require("cli.env_file")

local Docker = {}

-- Seconds to wait for /health after `up` (the first boot initializes MySQL).
Docker.timeout = 180

local function capture(command)
    local handle = io.popen(command .. " 2>/dev/null")
    if not handle then return nil end
    local output = handle:read("*a") or ""
    handle:close()
    return (output:gsub("%s+$", ""))
end

-- "docker compose" (v2) or "docker-compose" (v1), or nil.
function Docker.compose()
    if fs.execute("docker compose version >/dev/null 2>&1") then return "docker compose" end
    if fs.execute("docker-compose version >/dev/null 2>&1") then return "docker-compose" end
    return nil
end

function Docker.available()
    return fs.execute("docker --version >/dev/null 2>&1")
end

-- Checks docker, the compose plugin, the daemon and docker-compose.yml.
local function preflight()
    if not Docker.available() then
        cli_output.print_error("Docker is not installed: https://docs.docker.com/get-docker/")
        return nil
    end
    local compose = Docker.compose()
    if not compose then
        cli_output.print_error("Docker Compose is not available (docker compose / docker-compose)")
        return nil
    end
    if not fs.execute("docker info >/dev/null 2>&1") then
        cli_output.print_error("The Docker daemon is not running: start Docker Desktop (or the docker service)")
        return nil
    end
    if not fs.exists("docker-compose.yml") then
        cli_output.print_error("docker-compose.yml not found: run this from the project root")
        return nil
    end
    return compose
end

local function env_value(key, default)
    local text = fs.read(".env")
    local value = text and EnvFile.get(text, key)
    if value == nil or value == "" then return default end
    return value
end

-- Compose's default project name: the directory name, lowercased.
function Docker.project_name(directory)
    local name = (directory or fs.cwd()):match("([^/]+)/*$") or "app"
    return (name:lower():gsub("[^a-z0-9_-]", ""))
end

function Docker.mysql_volume_exists()
    local name = Docker.project_name() .. "_mysql-data"
    local volumes = capture("docker volume ls -q") or ""
    for line in volumes:gmatch("[^\n]+") do
        if line == name then return true end
    end
    return false
end

local function wait_for_health(port)
    local url = "http://127.0.0.1:" .. port .. "/health"
    io.write("  waiting for " .. url .. " ")
    io.flush()
    local started = os.time()
    while os.difftime(os.time(), started) < Docker.timeout do
        if fs.execute("curl -fsS -o /dev/null --max-time 2 " .. fs.shell_quote(url) .. " 2>/dev/null") then
            io.write("\n")
            return true
        end
        io.write(".")
        io.flush()
        fs.execute("sleep 2")
    end
    io.write("\n")
    return false
end

-- options.build: rebuild the image; options.fresh: rebuild without cache;
-- options.logs: follow the app logs afterwards.
function Docker.run(options)
    options = options or {}
    local title = options.build and "Rebuilding and restarting the Docker stack" or "Starting the Docker stack (hot reload)"
    cli_output.print_header(title)
    local compose = preflight()
    if not compose then return false end

    local created, env_error = EnvFile.ensure(".")
    if created == nil then
        cli_output.print_error("unable to create .env: " .. tostring(env_error))
        return false
    elseif created then
        cli_output.print_success(".env created from .env.example with random secrets")
    end

    if options.fresh then
        cli_output.print_info("Building the app image without cache...")
        if not fs.execute(compose .. " build --no-cache app") then
            cli_output.print_error("docker build failed")
            return false
        end
    end
    local command = compose .. " up -d" .. (options.build and not options.fresh and " --build" or "")
    cli_output.print_debug("$ " .. command)
    if not fs.execute(command) then
        cli_output.print_error("docker compose up failed (see the output above)")
        return false
    end

    local port = env_value("APP_PORT", "8080")
    if not wait_for_health(port) then
        cli_output.print_error("the app did not answer /health within " .. Docker.timeout .. "s")
        cli_output.print_info("Check the logs: " .. compose .. " logs app")
        return false
    end

    cli_output.print_success("App running with hot reload: edit files under src/, views/ or app.lua and reload")
    print("")
    print("  App:    http://127.0.0.1:" .. port .. "   (/health, /ready, /api/hello?name=Ada)")
    print("  MySQL:  127.0.0.1:" .. env_value("DB_FORWARD_PORT", "3307") .. "   user " .. env_value("DB_USER", "crescent")
        .. ", database " .. env_value("DB_NAME", "?"))
    print("")
    cli_output.print_info("Logs: lua cli.lua run --logs  ·  rebuild: lua cli.lua rerun  ·  stop: lua cli.lua stop")
    cli_output.print_info("CLI inside the container: docker compose exec app bin/crescent <command>")

    if options.logs then
        print("")
        fs.execute(compose .. " logs -f app")
    end
    return true
end

-- Parses `[--logs|-f] [--fresh]` for run/rerun.
function Docker.parse(args)
    local options = {}
    for _, value in ipairs(args or {}) do
        if value == "--logs" or value == "-f" then options.logs = true
        elseif value == "--fresh" then options.fresh = true
        else return nil, "unknown option: " .. tostring(value) end
    end
    return options
end

local function with_options(build)
    return function(args)
        local options, err = Docker.parse(args)
        if not options then
            cli_output.print_error(err)
            return false
        end
        options.build = build or options.fresh
        return Docker.run(options)
    end
end

Docker.run_command = with_options(false)
Docker.rerun_command = with_options(true)

-- Stops and removes the containers; volumes (database, uploads) are kept.
function Docker.stop()
    cli_output.print_header("Stopping the Docker stack")
    local compose = preflight()
    if not compose then return false end
    if not fs.execute(compose .. " down") then
        cli_output.print_error("docker compose down failed")
        return false
    end
    cli_output.print_success("Stopped (database and uploads are kept in Docker volumes)")
    return true
end

return Docker
