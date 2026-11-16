local json = require("crescent.json")

local Response = {}
Response.__index = Response

local function is_safe_header_value(value)
    if type(value) == "number" then return true end
    if type(value) == "table" then
        for _, item in ipairs(value) do
            if not is_safe_header_value(item) then return false end
        end
        return true
    end
    return type(value) == "string" and not value:find("[%z\r\n]")
end

Response.is_safe_header_value = is_safe_header_value

function Response.new(writer)
    writer.headers = writer.headers or {}
    return setmetatable({ writer = writer }, Response)
end

function Response:status(code)
    self.writer.status = code
    return self
end

local function check_header(name, value, level)
    if type(name) ~= "string" or not name:match("^[%w!#$%%&'*+%-.^_`|~]+$") then
        error("invalid response header name: " .. tostring(name), level + 1)
    end
    if value ~= nil and not is_safe_header_value(value) then
        error("invalid response header value for " .. name, level + 1)
    end
end

-- Header names are case-insensitive: returns the key already used in the
-- writer for `name`, if any.
local function existing_key(headers, name)
    if headers[name] ~= nil then return name end
    local lower = name:lower()
    for key in pairs(headers) do
        if type(key) == "string" and key:lower() == lower then return key end
    end
    return nil
end

-- Sets (or with nil, removes) a header, replacing any value stored under a
-- differently-cased name.
function Response:header(name, value)
    check_header(name, value, 2)
    local headers = self.writer.headers
    local key = existing_key(headers, name)
    if key and key ~= name then headers[key] = nil end
    headers[name] = value
    return self
end

-- Adds a value without replacing the existing ones; repeated headers (e.g.
-- several Set-Cookie) become a list, which nginx sends as separate lines.
function Response:append_header(name, value)
    if value == nil then error("append_header requires a value for " .. tostring(name), 2) end
    check_header(name, value, 2)
    local headers = self.writer.headers
    local key = existing_key(headers, name) or name
    local current = headers[key]
    local list = {}
    if type(current) == "table" then
        for _, item in ipairs(current) do list[#list + 1] = item end
    elseif current ~= nil then
        list[1] = current
    end
    if type(value) == "table" then
        for _, item in ipairs(value) do list[#list + 1] = item end
    else
        list[#list + 1] = value
    end
    headers[key] = #list == 1 and list[1] or list
    return self
end

-- Returns the value (string, number or list) of a header, case-insensitively.
function Response:get_header(name)
    if type(name) ~= "string" then return nil end
    local headers = self.writer.headers
    local key = existing_key(headers, name)
    return key and headers[key] or nil
end

-- Registers `fn(response)` to run once, right before the response is
-- flushed. Hooks may still change headers (the session middleware writes its
-- Set-Cookie here); an error in a hook aborts the send, so the application
-- answers 500 instead.
function Response:before_flush(fn)
    assert(type(fn) == "function", "before_flush expects a function")
    local hooks = self.writer.before_flush
    if not hooks then
        hooks = {}
        self.writer.before_flush = hooks
    end
    hooks[#hooks + 1] = fn
    return self
end

function Response:headers(values)
    for name, value in pairs(values or {}) do self:header(name, value) end
    return self
end

function Response:json(value)
    local body, err = json.encode(value)
    if not body then error(err or "JSON encoding failed", 2) end
    return self:header("Content-Type", "application/json; charset=utf-8"):send(body)
end

function Response:text(value)
    return self:header("Content-Type", "text/plain; charset=utf-8"):send(value or "")
end

function Response:html(value)
    return self:header("Content-Type", "text/html; charset=utf-8"):send(value or "")
end

function Response:send(body)
    local writer = self.writer
    if writer.sent then return self end
    writer.status = writer.status or 200
    writer.body = body or ""
    local hooks = writer.before_flush
    if hooks then
        writer.before_flush = nil
        for _, hook in ipairs(hooks) do hook(self) end
    end
    writer.sent = true
    if writer.flush then writer.flush(writer) end
    return self
end

function Response:is_sent()
    return self.writer.sent == true
end

function Response:no_content()
    self.writer.status = 204
    return self:send("")
end

-- Redirects are local by default. External targets require
-- `{ allowed_hosts = { "example.com" } }`, which prevents open redirects
-- built from user input.
function Response:redirect(location, code, options)
    options = options or {}
    if type(location) ~= "string" or not is_safe_header_value(location) then
        return self:error(400, "invalid redirect location", nil, "invalid_redirect")
    end
    local host = location:match("^[hH][tT][tT][pP][sS]?://([^/%?#]+)")
    if host then
        local allowed = false
        for _, candidate in ipairs(options.allowed_hosts or {}) do
            if candidate == host:lower() then allowed = true break end
        end
        if not allowed then
            return self:error(400, "external redirect not allowed", nil, "invalid_redirect")
        end
    elseif not location:match("^/") or location:match("^//") or location:match("^/\\") then
        return self:error(400, "invalid redirect location", nil, "invalid_redirect")
    end
    self:header("Location", location)
    self.writer.status = code or 302
    return self:send("")
end

function Response:error(code, message, details, identifier)
    local payload = {
        code = identifier or "http_error",
        error = message or "internal error",
        status = code or 500,
    }
    if details then payload.details = details end
    return self:status(code or 500):json(payload)
end

return Response
