local Router = require("crescent.router")
local Context = require("crescent.context")
local Request = require("crescent.request")
local Response = require("crescent.response")
local View = require("crescent.view")
local Database = require("crescent.database")

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

-- An upstream X-Request-Id (from a trusted proxy) wins, then nginx's own
-- $request_id, then a locally generated one.
local function request_id(request)
    if valid_request_id(request.upstream_request_id) then return request.upstream_request_id end
    if valid_request_id(request.request_id) then return request.request_id end
    return make_request_id()
end

local function merge(left, right)
    local result = {}
    for key, value in pairs(left or {}) do result[key] = value end
    for key, value in pairs(right or {}) do result[key] = value end
    return result
end

-- `config.logger` may be a crescent.logger instance or a plain
-- function(level, message, fields).
local function make_logger(logger)
    if type(logger) == "function" then return logger end
    logger = logger or require("crescent.logger").new()
    return function(level, message, fields) logger:log(level, message, fields) end
end

-- Relative paths are resolved against `config.root` when given, otherwise
-- against the OpenResty prefix (`-p`) — not the process working directory,
-- which differs between dev and production.
local function resolve_path(path, root)
    if path:sub(1, 1) == "/" then return path end
    if root then return root:gsub("/$", "") .. "/" .. path end
    local prefix = ngx and ngx.config and ngx.config.prefix and ngx.config.prefix()
    if prefix and prefix ~= "" then
        return prefix:gsub("/$", "") .. "/" .. path
    end
    return path
end

function Application.new(config)
    config = config or {}
    if config.error_handler ~= nil then
        assert(type(config.error_handler) == "function", "error_handler must be a function")
    end
    local merged = merge({ debug = false, environment = "production" }, config)
    -- The database adapter connects lazily (pooled per worker), so configuring
    -- it at boot — even in init_by_lua — opens no connection.
    local db = config.db
    if not db and type(config.database) == "table" and config.database.database then
        db = Database.configure(config.database)
    end
    return setmetatable({
        db = db,
        config = merged,
        router = Router.new(),
        view_renderer = config.view_renderer
            or View.new(resolve_path(config.views_root or "views", config.root), { cache = not merged.debug }),
        error_handler = config.error_handler,
        logger = make_logger(config.logger),
        middleware = {},
    }, Application)
end

function Application:get(path, action, name) self.router:add("GET", path, action, name) return self end
function Application:post(path, action, name) self.router:add("POST", path, action, name) return self end
function Application:put(path, action, name) self.router:add("PUT", path, action, name) return self end
function Application:patch(path, action, name) self.router:add("PATCH", path, action, name) return self end
function Application:delete(path, action, name) self.router:add("DELETE", path, action, name) return self end
function Application:options(path, action, name) self.router:add("OPTIONS", path, action, name) return self end
function Application:head(path, action, name) self.router:add("HEAD", path, action, name) return self end
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

function Application:_dispatch_route(ctx)
    local action, params, route = self.router:match(ctx.method, ctx.path)
    -- HEAD falls back to GET; nginx strips the body for HEAD responses.
    if not action and ctx.method == "HEAD" then
        action, params, route = self.router:match("GET", ctx.path)
    end
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

-- Actions may return a table/string instead of writing a response; it is sent
-- as 200 JSON/text. An action that neither responds nor returns a value is a
-- bug and produces a 500 instead of an empty 200.
function Application:_finalize(ctx, result)
    if ctx.res:is_sent() then return result end
    if getmetatable(result) == Response then result = nil end
    if type(result) == "table" then return ctx:json(200, result) end
    if type(result) == "string" then return ctx:text(200, result) end
    self.logger("error", string.format("[%s] %s %s produced no response", ctx.request_id, ctx.method, ctx.path),
        { request_id = ctx.request_id, method = ctx.method, path = ctx.path })
    return ctx:error(500, "internal server error", nil, "empty_response")
end

-- Errors raised as tables with a 4xx `status` (e.g. Model:find_or_fail) are
-- client errors, not failures: answer them without logging an error.
local function client_error(err)
    return type(err) == "table" and type(err.status) == "number" and err.status >= 400 and err.status < 500
end

function Application:_handle_error(ctx, err)
    if client_error(err) and not ctx.res:is_sent() then
        local message = err.status == 404 and "resource not found" or (err.public_message or "request failed")
        return ctx:error(err.status, message, self.config.debug and err.message or nil, err.code or "http_error")
    end
    self.logger("error", string.format("[%s] %s %s failed: %s", ctx.request_id, ctx.method, ctx.path, tostring(err)),
        { request_id = ctx.request_id, method = ctx.method, path = ctx.path })
    if ctx.res:is_sent() then return end
    if self.error_handler then
        local handled, response = pcall(self.error_handler, ctx, err)
        if handled and response ~= nil and ctx.res:is_sent() then return response end
        if not handled then
            self.logger("error", string.format("[%s] error_handler failed: %s", ctx.request_id, tostring(response)),
                { request_id = ctx.request_id })
        end
    end
    return ctx:error(500, "internal server error", self.config.debug and err or nil, "internal_error")
end

function Application:handle(request, writer)
    request.request_id = request_id(request)
    local ctx = Context.new(request, writer)
    ctx.app = self
    ctx.config = self.config
    ctx.db = self.db
    ctx.view_renderer = self.view_renderer
    ctx.debug = self.config.debug
    ctx.res:header("X-Request-Id", ctx.request_id)
    if request.body_error then
        local details = self.config.debug and request.body_error or nil
        return ctx:error(request.body_error_status or 400, request.body_error_message or "malformed request body",
            details, request.body_error_code or "malformed_body")
    end
    local middleware = self.middleware
    local function dispatch(index)
        if index <= #middleware then
            local next_called = false
            local function next_middleware()
                assert(not next_called, "middleware called next more than once")
                next_called = true
                return dispatch(index + 1)
            end
            return middleware[index](ctx, next_middleware)
        end
        return self:_dispatch_route(ctx)
    end
    local ok, result = xpcall(function() return dispatch(1) end, debug.traceback)
    if not ok then return self:_handle_error(ctx, result) end
    local finalized, final_result = pcall(self._finalize, self, ctx, result)
    if not finalized then return self:_handle_error(ctx, final_result) end
    return final_result
end

local function ngx_writer(ngx_api)
    return {
        headers = {},
        sent = false,
        flush = function(writer)
            ngx_api.status = writer.status
            for name, value in pairs(writer.headers) do ngx_api.header[name] = value end
            if writer.body ~= "" then ngx_api.print(writer.body) end
        end,
    }
end

-- Entry point for content_by_lua. `ngx_api` defaults to the global `ngx` and
-- exists so tests can drive the full request path with a fake.
function Application:run(ngx_api)
    ngx_api = ngx_api or ngx
    if not ngx_api then error("Application:run() requires OpenResty ngx") end
    local request = Request.from_ngx(ngx_api, self.config)
    local ok, result = pcall(self.handle, self, request, ngx_writer(ngx_api))
    Request.cleanup(request)
    if not ok then error(result, 0) end
    return result
end

return Application
