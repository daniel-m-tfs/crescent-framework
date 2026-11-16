local Router = require("crescent.router")
local Context = require("crescent.context")
local View = require("crescent.view")
local json_ok, cjson = pcall(require, "cjson.safe")
if not json_ok then cjson = nil end

local Application = {}
Application.__index = Application
local request_counter = 0

local function valid_request_id(value)
    return type(value) == "string"
        and #value > 0
        and #value <= 128
        and value:match("^[%w%._%-]+$") ~= nil
end

local function make_request_id()
    request_counter = request_counter + 1
    local now = ngx and ngx.now and ngx.now() or os.time()
    local worker = ngx and ngx.worker and ngx.worker.pid and ngx.worker.pid() or 0
    return string.format("crescent-%x-%x-%x", math.floor(now * 1000), worker, request_counter)
end

local function request_id(request)
    if valid_request_id(request.request_id) then return request.request_id end
    return make_request_id()
end

local function decode_form_component(value)
    value = value:gsub("+", " ")
    if value:find("%%[^0-9a-fA-F]", 1) or value:find("%%.$") then return nil end
    local decoded = value:gsub("%%([0-9a-fA-F][0-9a-fA-F])", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded:find("%%", 1, true) and nil or decoded
end

local function parse_form(body)
    local result = {}
    for pair in body:gmatch("[^&]+") do
        local key, value = pair:match("^([^=]*)=(.*)$")
        if key == nil then key, value = pair, "" end
        key, value = decode_form_component(key), decode_form_component(value)
        if not key or not value or key == "" then return nil, "malformed form body" end
        if result[key] == nil then
            result[key] = value
        elseif type(result[key]) == "table" then
            result[key][#result[key] + 1] = value
        else
            result[key] = { result[key], value }
        end
    end
    return result
end

local function merge(left, right)
    local result = {}
    for key, value in pairs(left or {}) do result[key] = value end
    for key, value in pairs(right or {}) do result[key] = value end
    return result
end

function Application.new(config)
    config = config or {}
    if config.error_handler ~= nil then
        assert(type(config.error_handler) == "function", "error_handler must be a function")
    end
    return setmetatable({
        config = merge({ debug = false, environment = "production" }, config),
        router = Router.new(),
        view_renderer = config.view_renderer or View.new(config.views_root or "views", { cache = not config.debug }),
        error_handler = config.error_handler,
        middleware = {},
    }, Application)
end

function Application:get(path, action, name) return self.router:add("GET", path, action, name) and self end
function Application:post(path, action, name) return self.router:add("POST", path, action, name) and self end
function Application:put(path, action, name) return self.router:add("PUT", path, action, name) and self end
function Application:patch(path, action, name) return self.router:add("PATCH", path, action, name) and self end
function Application:delete(path, action, name) return self.router:add("DELETE", path, action, name) and self end
function Application:group(prefix, callback)
    self.router:group(prefix, function() callback(self) end)
    return self
end
function Application:route(name) return self.router:find(name) end
function Application:use(middleware)
    assert(type(middleware) == "function", "middleware must be a function")
    self.middleware[#self.middleware + 1] = middleware
    return self
end
function Application:validated(schema, action, source)
    assert(type(schema) == "table", "validation schema must be a table")
    assert(type(action) == "function", "validated action must be a function")
    return function(ctx)
        local valid, errors = ctx:validate(schema, source)
        if not valid then return ctx:error(422, "validation failed", errors, "validation_failed") end
        return action(ctx)
    end
end
function Application:on_error(handler) self.error_handler = handler; return self end

function Application:handle(request, writer)
    request.request_id = request_id(request)
    local ctx = Context.new(request, writer)
    ctx.view_renderer = self.view_renderer
    ctx.debug = self.config.debug
    ctx.res:header("X-Request-Id", ctx.request_id)
    if request.body_error then
        return ctx:error(400, request.body_error, nil, request.body_error_code)
    end
    local function dispatch(index)
        if index <= #self.middleware then
            local middleware = self.middleware[index]
            local next_called = false
            local function next_middleware()
                assert(not next_called, "middleware called next more than once")
                next_called = true
                return dispatch(index + 1)
            end
            return middleware(ctx, next_middleware)
        end
        local action, params, route = self.router:match(ctx.method, ctx.path)
        if not action then
            local allowed = self.router:allowed_methods(ctx.path)
            if #allowed > 0 then
                ctx.res:header("Allow", table.concat(allowed, ", "))
                return ctx:error(405, "method not allowed", nil, "method_not_allowed")
            end
            return ctx:error(404, "route not found", nil, "route_not_found")
        end
        ctx.params = params
        ctx.route = route
        return action(ctx)
    end
    local ok, result = xpcall(function() return dispatch(1) end, debug.traceback)
    if not ok then
        if self.error_handler then
            local handled, handler_error = pcall(self.error_handler, ctx, result)
            if handled and handler_error ~= nil then return handler_error end
        end
        return ctx:error(500, "internal server error", self.config.debug and result or nil, "internal_error")
    end
    return result
end

function Application:run()
    if not ngx then error("Application:run() requires OpenResty ngx") end
    local headers = {}
    for key, value in pairs(ngx.req.get_headers()) do headers[string.lower(key)] = value end
    local request = {
        method = ngx.req.get_method(),
        path = ngx.var.uri or "/",
        headers = headers,
        query = ngx.req.get_uri_args(),
        request_id = ngx.var.request_id,
    }
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    request.raw_body = body
    local content_type = headers["content-type"] or ""
    if body and content_type:match("^application/json") then
        if not cjson then
            request.body_error = "JSON support is unavailable"
        else
            local decoded, decode_error = cjson.decode(body)
            if decoded == nil and decode_error then
                request.body_error = decode_error
            else
                request.body = decoded
            end
        end
    elseif body and content_type:match("^application/x%-www%-form%-urlencoded") then
        local decoded, decode_error = parse_form(body)
        if not decoded then
            request.body_error = decode_error
            request.body_error_code = "malformed_form"
        else
            request.body = decoded
        end
    else
        request.body = body
    end
    return self:handle(request, { headers = {}, sent = false })
end

return Application
