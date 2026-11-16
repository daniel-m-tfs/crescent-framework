local Response = require("crescent.response")
local Validation = require("crescent.validation")

local Context = {}
Context.__index = Context

function Context.new(request, writer)
    local headers = request.headers or {}
    local query = request.query or {}
    return setmetatable({
        req = request,
        res = Response.new(writer),
        method = request.method or "GET",
        path = request.path or "/",
        headers = headers,
        query = query,
        request_id = request.request_id,
        remote_addr = request.remote_addr,
        params = {},
        state = {},
        body = request.body,
        raw_body = request.raw_body,
    }, Context)
end

function Context:get_header(name)
    local value = self.headers[string.lower(name)]
    if type(value) == "table" then return value[1] end
    return value
end

-- Returns the token from `Authorization: Bearer <token>`, or nil.
function Context:get_bearer()
    local authorization = self:get_header("authorization")
    if type(authorization) ~= "string" then return nil end
    local token = authorization:match("^[Bb][Ee][Aa][Rr][Ee][Rr]%s+(%S+)%s*$")
    return token
end

function Context:header(name, value)
    self.res:header(name, value)
    return self
end

function Context:json(code, value)
    return self.res:status(code):json(value)
end

function Context:text(code, value)
    return self.res:status(code):text(value)
end

function Context:html(code, value)
    return self.res:status(code):html(value)
end

function Context:no_content()
    return self.res:no_content()
end

function Context:redirect(location, code, options)
    return self.res:redirect(location, code, options)
end

function Context:view(name, data, code)
    if not self.view_renderer then
        return self:error(500, "view renderer is not configured", nil, "view_renderer_unavailable")
    end
    local rendered, render_error = self.view_renderer:render(name, data or {})
    if not rendered then
        return self:error(500, "template rendering failed", self.debug and render_error or nil, "template_error")
    end
    return self:html(code or 200, rendered)
end

function Context:error(code, message, details, identifier)
    return self.res:error(code, message, details, identifier)
end

function Context:validate(schema, source)
    local data = self[source or "body"]
    local valid, errors = Validation.validate(data or {}, schema)
    self.validation_errors = errors
    return valid, errors
end

return Context
