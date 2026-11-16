-- Structured logging. Each entry is one JSON object written to the nginx
-- error log (or stderr outside OpenResty), with sensitive fields redacted.
--
--   local log = require("crescent.logger").new({ level = "info" })
--   log:info("user signed in", { user_id = 7, password = "x" })
--   -- {"level":"info","msg":"user signed in","user_id":7,"password":"[REDACTED]"}
local json = require("crescent.json")

local Logger = {}
Logger.__index = Logger

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }

-- Keys are matched case-insensitively as substrings, so `db_password`,
-- `X-Api-Key` and `refresh_token` are covered too.
Logger.SENSITIVE = {
    "password", "passwd", "secret", "token", "authorization", "cookie",
    "api_key", "apikey", "api-key", "credit_card", "card_number", "cvv", "private_key",
}
Logger.REDACTED = "[REDACTED]"

local MAX_DEPTH = 6
local MAX_STRING = 2048

local function is_sensitive(key, patterns)
    if type(key) ~= "string" then return false end
    key = key:lower()
    for _, pattern in ipairs(patterns) do
        if key:find(pattern, 1, true) then return true end
    end
    return false
end

local function redact(value, patterns, depth, seen)
    if type(value) == "string" then
        if #value > MAX_STRING then return value:sub(1, MAX_STRING) .. "...(truncated)" end
        return value
    end
    if type(value) ~= "table" then
        if type(value) == "function" or type(value) == "userdata" or type(value) == "thread" then
            return tostring(value)
        end
        return value
    end
    if depth > MAX_DEPTH then return "[max depth]" end
    if seen[value] then return "[circular]" end
    seen[value] = true
    local result = {}
    for key, item in pairs(value) do
        if is_sensitive(key, patterns) then
            result[key] = Logger.REDACTED
        else
            result[key] = redact(item, patterns, depth + 1, seen)
        end
    end
    seen[value] = nil
    return setmetatable(result, getmetatable(value) == json.array_mt and json.array_mt or nil)
end

-- Returns a redacted deep copy; the input is never modified.
function Logger.redact(value, extra_patterns)
    local patterns = Logger.SENSITIVE
    if extra_patterns then
        patterns = {}
        for _, pattern in ipairs(Logger.SENSITIVE) do patterns[#patterns + 1] = pattern end
        for _, pattern in ipairs(extra_patterns) do patterns[#patterns + 1] = pattern:lower() end
    end
    return redact(value, patterns, 1, {})
end

local function default_sink(level, line)
    if ngx and ngx.log then
        -- info maps to NOTICE: nginx's usual `error_log ... notice` would drop INFO.
        local ngx_level = ({ debug = ngx.DEBUG, info = ngx.NOTICE, warn = ngx.WARN, error = ngx.ERR })[level]
        ngx.log(ngx_level, line)
    else
        io.stderr:write(line, "\n")
    end
end

-- options: level ("debug"|"info"|"warn"|"error", default "info"),
-- fields (merged into every entry), redact (extra sensitive key patterns),
-- sink(level, line) (default: ngx.log / stderr).
function Logger.new(options)
    options = options or {}
    local level = options.level or "info"
    if not LEVELS[level] then error("invalid log level: " .. tostring(level), 2) end
    return setmetatable({
        threshold = LEVELS[level],
        fields = options.fields or {},
        extra_patterns = options.redact,
        sink = options.sink or default_sink,
    }, Logger)
end

function Logger:with(fields)
    local merged = {}
    for key, value in pairs(self.fields) do merged[key] = value end
    for key, value in pairs(fields or {}) do merged[key] = value end
    return setmetatable({
        threshold = self.threshold,
        fields = merged,
        extra_patterns = self.extra_patterns,
        sink = self.sink,
    }, Logger)
end

function Logger:enabled(level)
    return (LEVELS[level] or 0) >= self.threshold
end

function Logger:log(level, message, fields)
    if not self:enabled(level) then return end
    local entry = {}
    for key, value in pairs(self.fields) do entry[key] = value end
    for key, value in pairs(fields or {}) do entry[key] = value end
    entry = Logger.redact(entry, self.extra_patterns)
    entry.level = level
    entry.msg = tostring(message)
    local line = json.encode(entry)
    if not line then line = string.format('{"level":"%s","msg":"unserializable log entry"}', level) end
    self.sink(level, line)
end

function Logger:debug(message, fields) self:log("debug", message, fields) end
function Logger:info(message, fields) self:log("info", message, fields) end
function Logger:warn(message, fields) self:log("warn", message, fields) end
function Logger:error(message, fields) self:log("error", message, fields) end

return Logger
