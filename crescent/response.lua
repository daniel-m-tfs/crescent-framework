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

function Response:header(name, value)
    if type(name) ~= "string" or not name:match("^[%w!#$%%&'*+%-.^_`|~]+$") then
        error("invalid response header name: " .. tostring(name), 2)
    end
    if value ~= nil and not is_safe_header_value(value) then
        error("invalid response header value for " .. name, 2)
    end
    self.writer.headers[name] = value
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
    writer.sent = true
    writer.status = writer.status or 200
    writer.body = body or ""
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
