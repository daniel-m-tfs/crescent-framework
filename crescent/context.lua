local Response = require("crescent.response")

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
        params = {},
        state = {},
        body = request.body,
        raw_body = request.raw_body,
    }, Context)
end

function Context:get_header(name)
    return self.headers[string.lower(name)]
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
    local Validation = require("crescent.validation")
    local data = self[source or "body"]
    local valid, errors = Validation.validate(data or {}, schema)
    self.validation_errors = errors
    return valid, errors
end

return Context
