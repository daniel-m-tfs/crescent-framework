-- `server [start|stop|reload|status]`: wraps `openresty -p <root>/ -c <conf>`.
local cli_output = require("crescent.utils.cli_output")
local fs = require("cli.fs")

local Server = {}

local ACTIONS = { start = true, stop = true, reload = true, status = true }
local SIGNALS = { stop = "quit", reload = "reload" }

-- Override with OPENRESTY_BIN.
function Server.openresty_bin()
    local configured = os.getenv("OPENRESTY_BIN")
    if configured and configured ~= "" then return configured end
    for _, candidate in ipairs({
        "/opt/homebrew/opt/openresty/bin/openresty",
        "/usr/local/openresty/bin/openresty",
        "/opt/openresty/bin/openresty",
    }) do
        local file = io.open(candidate, "r")
        if file then file:close() return candidate end
    end
    return "openresty"
end

-- Parses `[action] [--conf file] [--env name]`.
function Server.parse(args)
    local options = { action = "start", conf = "nginx.conf" }
    local index = 1
    while args[index] do
        local value = args[index]
        if value == "--conf" or value == "--env" then
            local option_value = args[index + 1]
            if not option_value then return nil, value .. " requires a value" end
            options[value:sub(3)] = option_value
            index = index + 2
        elseif ACTIONS[value] and index == 1 then
            options.action = value
            index = index + 1
        else
            return nil, "unknown server argument: " .. tostring(value)
        end
    end
    if options.env and not options.env:match("^[%a_][%w_]*$") then
        return nil, "invalid environment name: " .. options.env
    end
    return options
end

local function pid_file(root, conf)
    local content = fs.read(fs.join(root, conf)) or ""
    local configured = content:match("\n%s*pid%s+([^;%s]+)%s*;")
    return fs.join(root, configured or "logs/nginx.pid")
end

local function running_pid(root, conf)
    local content = fs.read(pid_file(root, conf))
    local pid = content and content:match("^%s*(%d+)%s*$")
    if pid and fs.execute("kill -0 " .. pid .. " 2>/dev/null") then return pid end
    return nil
end

-- Builds the shell command; exposed for tests.
function Server.command(options, root)
    local parts = {}
    local env = options.env or os.getenv("APP_ENV")
    if env and env ~= "" then parts[#parts + 1] = "APP_ENV=" .. fs.shell_quote(env) end
    parts[#parts + 1] = fs.shell_quote(Server.openresty_bin())
    parts[#parts + 1] = "-p " .. fs.shell_quote(root:gsub("/$", "") .. "/")
    parts[#parts + 1] = "-c " .. fs.shell_quote(options.conf)
    if SIGNALS[options.action] then parts[#parts + 1] = "-s " .. SIGNALS[options.action] end
    return table.concat(parts, " ")
end

function Server.run(args, root)
    local options, err = Server.parse(args or {})
    if not options then
        cli_output.print_error(err)
        return false
    end
    root = root or fs.cwd()
    if not fs.exists(fs.join(root, options.conf)) then
        cli_output.print_error("configuration not found: " .. fs.join(root, options.conf))
        return false
    end

    local pid = running_pid(root, options.conf)
    if options.action == "status" then
        if pid then print("running (pid " .. pid .. ")") else print("stopped") end
        return true
    end
    if options.action == "start" and pid then
        cli_output.print_error("already running (pid " .. pid .. ")")
        return false
    end
    if options.action ~= "start" and not pid then
        cli_output.print_error("not running")
        return false
    end

    if options.action == "start" then
        for _, directory in ipairs({ "logs", "tmp" }) do fs.mkdir_p(fs.join(root, directory)) end
    end
    local command = Server.command(options, root)
    cli_output.print_info(command)
    io.stdout:flush()
    if not fs.execute(command) then
        cli_output.print_error("openresty " .. options.action .. " failed (see logs/error.log)")
        return false
    end
    return true
end

return Server
