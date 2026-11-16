local Config = {}

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function invalid(message)
    error("invalid configuration: " .. message, 3)
end

function Config.validate(config)
    if type(config) ~= "table" then invalid("expected a table") end
    if type(config.environment) ~= "string" or config.environment == "" then
        invalid("environment must be a non-empty string")
    end
    if type(config.debug) ~= "boolean" then invalid("debug must be boolean") end
    if type(config.server) ~= "table" then invalid("server must be a table") end

    local server = config.server
    if type(server.host) ~= "string" or server.host == "" then
        invalid("server.host must be a non-empty string")
    end
    if not is_integer(server.port) or server.port < 1 or server.port > 65535 then
        invalid("server.port must be an integer between 1 and 65535")
    end
    if not is_integer(server.max_body_size) or server.max_body_size < 1 then
        invalid("server.max_body_size must be a positive integer")
    end
    return config
end

function Config.load(environment)
    environment = environment or os.getenv("APP_ENV") or "development"
    if type(environment) ~= "string" or not environment:match("^[%a_][%w_]*$") then
        invalid("environment name is invalid")
    end

    local ok, config = pcall(require, "config." .. environment)
    if not ok then error("unable to load configuration for " .. environment .. ": " .. tostring(config), 2) end
    Config.validate(config)
    return config
end

return Config