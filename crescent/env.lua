-- Environment access. Precedence: process environment > .env file > default.
-- `.env` is a local-development convenience; production values must come from
-- the process environment. Under OpenResty every variable read here must also
-- be declared with an `env NAME;` directive in nginx.conf, because nginx
-- clears the environment of its worker processes.
local Env = {}

local cache

local function unquote(value)
    local quoted = value:match('^"(.-)"$') or value:match("^'(.-)'$")
    if quoted ~= nil then return quoted end
    value = value:gsub("%s+#.*$", "")
    return (value:match("^%s*(.-)%s*$"))
end

function Env.parse(text)
    local values = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", ""):match("^%s*(.-)%s*$")
        if line ~= "" and not line:match("^#") then
            line = line:gsub("^export%s+", "")
            local key, value = line:match("^([%a_][%w_]*)%s*=%s*(.*)$")
            if key then values[key] = unquote(value) end
        end
    end
    return values
end

local function default_path()
    local prefix = ngx and ngx.config and ngx.config.prefix and ngx.config.prefix()
    if prefix and prefix ~= "" then return prefix:gsub("/$", "") .. "/.env" end
    return ".env"
end

function Env.load(path)
    local file = io.open(path or default_path(), "r")
    if not file then return {} end
    local text = file:read("*a")
    file:close()
    return Env.parse(text)
end

function Env.get(key, default)
    local value = os.getenv(key)
    if value ~= nil and value ~= "" then return value end
    cache = cache or Env.load()
    value = cache[key]
    if value ~= nil and value ~= "" then return value end
    return default
end

function Env.number(key, default)
    local value = Env.get(key)
    if value == nil then return default end
    local number = tonumber(value)
    if number == nil then error("environment variable " .. key .. " must be a number", 2) end
    return number
end

function Env.boolean(key, default)
    local value = Env.get(key)
    if value == nil then return default end
    value = value:lower()
    if value == "true" or value == "1" or value == "yes" then return true end
    if value == "false" or value == "0" or value == "no" then return false end
    error("environment variable " .. key .. " must be a boolean", 2)
end

function Env.clear_cache()
    cache = nil
end

return Env
