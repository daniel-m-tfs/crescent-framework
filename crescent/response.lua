local json_ok, cjson = pcall(require, "cjson.safe")
if not json_ok then cjson = nil end

local Response = {}
Response.__index = Response

function Response.new(writer)
    return setmetatable({ writer = writer }, Response)
end

function Response:status(code)
    self.writer.status = code
    return self
end

function Response:header(name, value)
    self.writer.headers[name] = value
    return self
end

function Response:json(value)
    if not cjson then error("cjson.safe is required for JSON responses") end
    local body, err = cjson.encode(value)
    if not body then error(err or "JSON encoding failed") end
    return self:header("Content-Type", "application/json; charset=utf-8"):send(body)
end

function Response:text(value)
    return self:header("Content-Type", "text/plain; charset=utf-8"):send(value or "")
end

function Response:html(value)
    return self:header("Content-Type", "text/html; charset=utf-8"):send(value or "")
end

function Response:send(body)
    if self.writer.sent then return self end
    self.writer.sent = true
    self.writer.status = self.writer.status or 200
    if ngx then
        ngx.status = self.writer.status
        for name, value in pairs(self.writer.headers) do ngx.header[name] = value end
        ngx.say(body or "")
    else
        self.writer.body = body or ""
    end
    return self
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
