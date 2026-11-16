local Response = require("crescent.response")
local Validation = require("crescent.validation")
local Cookie = require("crescent.cookie")

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
        files = request.files or {},
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

-- Per-request helpers available in every template rendered with ctx:view.
-- csrf_field() returns HTML: print it raw with <%- csrf_field() %>.
local function view_data(ctx, data)
    local merged = {}
    if ctx.session then
        merged.csrf_token = function() return ctx:csrf_token() end
        merged.csrf_field = function() return require("crescent.middleware.csrf").field(ctx) end
    end
    for key, value in pairs(data or {}) do merged[key] = value end
    return merged
end

-- ctx:view(name, data[, status | { status =, layout = }]). With a layout,
-- the page is rendered first and handed to the layout as `content` (print it
-- with <%- content %>); the layout sees the same data. `config.view_layout`
-- sets a default layout; pass `layout = false` to render without it.
function Context:view(name, data, options)
    if type(options) ~= "table" then options = { status = options } end
    if not self.view_renderer then
        return self:error(500, "view renderer is not configured", nil, "view_renderer_unavailable")
    end
    local merged = view_data(self, data)
    local rendered, render_error = self.view_renderer:render(name, merged)
    local layout = options.layout
    if layout == nil then layout = self.config and self.config.view_layout end
    if rendered and layout then
        rendered, render_error = self.view_renderer:render_layout(layout, rendered, merged)
    end
    if not rendered then
        return self:error(500, "template rendering failed", self.debug and render_error or nil, "template_error")
    end
    return self:html(options.status or 200, rendered)
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

-- Cookies -----------------------------------------------------------------

function Context:cookies()
    if not self._cookies then self._cookies = Cookie.parse(self.headers.cookie) end
    return self._cookies
end

function Context:cookie(name)
    return self:cookies()[name]
end

function Context:_secrets()
    if not self._cookie_secrets then self._cookie_secrets = Cookie.secrets(self.config) end
    return self._cookie_secrets
end

-- Returns the value of a cookie written with { signed = true }, or nil when
-- it is missing or its signature does not match any configured secret.
function Context:signed_cookie(name)
    local raw = self:cookie(name)
    if raw == nil then return nil end
    return Cookie.unsign(name, raw, self:_secrets())
end

-- Setting the same cookie twice in a request keeps only the last value.
function Context:set_cookie(name, value, options)
    local settings = {}
    for key, option in pairs(options or {}) do settings[key] = option end
    if settings.secure == nil then settings.secure = not self.debug end
    if type(value) == "number" then value = tostring(value) end
    if settings.signed and type(value) == "string" then
        value = Cookie.sign(name, value, self:_secrets()[1])
    end
    local header = Cookie.serialize(name, value, settings)
    local current = self.res:get_header("Set-Cookie")
    if type(current) ~= "table" then current = { current } end
    local kept = {}
    local prefix = name .. "="
    for _, item in ipairs(current) do
        if item:sub(1, #prefix) ~= prefix then kept[#kept + 1] = item end
    end
    kept[#kept + 1] = header
    self.res:header("Set-Cookie", #kept == 1 and kept[1] or kept)
    return self
end

-- `options` must carry the same path/domain the cookie was set with.
function Context:clear_cookie(name, options)
    local settings = {}
    for key, option in pairs(options or {}) do settings[key] = option end
    settings.signed = nil
    settings.max_age = 0
    settings.expires = 0
    return self:set_cookie(name, "", settings)
end

-- CSRF and uploads --------------------------------------------------------

function Context:csrf_token()
    return require("crescent.middleware.csrf").token(self)
end

-- Moves an uploaded file out of the temporary directory. See crescent.upload.
function Context:save_upload(file, destination, options)
    return require("crescent.upload").save(file, destination, self.config, options)
end

return Context
