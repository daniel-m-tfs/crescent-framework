-- CORS middleware.
--
--   cors.create({
--       origins = { "https://app.example" } | "*" | function(origin, ctx) -> bool,
--       methods = { "GET", "POST", ... },
--       allowed_headers = { "Content-Type", "Authorization" },
--       expose_headers = { "X-Request-Id" },
--       credentials = false,
--       max_age = 600,
--       block = false,   -- true: answer 403 to non-preflight requests from other origins
--   })
--
-- Preflights (OPTIONS + Access-Control-Request-Method) are answered here with
-- 204, before routing, so routes do not need an OPTIONS handler. A matched
-- origin is reflected (never "*" when credentials are enabled) together with
-- `Vary: Origin` so caches do not mix responses between origins.
local Response = require("crescent.response")

local Cors = {}

local DEFAULT_METHODS = { "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE" }
local DEFAULT_HEADERS = { "Content-Type", "Authorization" }
-- CORS-safelisted request headers are always allowed.
local SAFELISTED = { accept = true, ["accept-language"] = true, ["content-language"] = true }

local function trim(value)
    return (value:match("^%s*(.-)%s*$"))
end

local function as_list(value, default)
    if value == nil then return default end
    if type(value) == "string" then
        local list = {}
        for item in value:gmatch("[^,]+") do
            item = trim(item)
            if item ~= "" then list[#list + 1] = item end
        end
        return list
    end
    assert(type(value) == "table", "CORS list options must be a list or a comma-separated string")
    return value
end

local function lookup(list, transform)
    local set = {}
    for _, item in ipairs(list) do set[transform and transform(item) or item] = true end
    return set
end

local function safe_join(list, name)
    local joined = table.concat(list, ", ")
    if not Response.is_safe_header_value(joined) then error("invalid CORS " .. name, 3) end
    return joined
end

local function origin_matcher(origins)
    if origins == "*" then return function() return true end, true end
    if type(origins) == "function" then return origins, false end
    if type(origins) == "string" then origins = { origins } end
    assert(type(origins) == "table", "CORS origins must be \"*\", a list or a function")
    for _, origin in ipairs(origins) do
        assert(origin ~= "*", "use origins = \"*\" instead of a list containing \"*\"")
        assert(Response.is_safe_header_value(origin), "invalid CORS origin")
    end
    local allowed = lookup(origins)
    return function(origin) return allowed[origin] == true end, false
end

local function add_vary(ctx, value)
    local current = ctx.res:get_header("Vary")
    if type(current) == "table" then current = table.concat(current, ", ") end
    if current and current ~= "" then
        for item in tostring(current):gmatch("[^,]+") do
            if trim(item):lower() == value:lower() then return end
        end
        value = current .. ", " .. value
    end
    ctx:header("Vary", value)
end

local function forbidden(ctx, message, code)
    return ctx:error(403, message, nil, code)
end

function Cors.create(options)
    options = options or {}
    local origins = options.origins
    if origins == nil then origins = options.origin end
    if origins == nil then origins = "*" end
    local matches, wildcard = origin_matcher(origins)
    if options.credentials and wildcard then
        error("CORS credentials require an explicit origin list or function", 2)
    end

    local methods = as_list(options.methods, DEFAULT_METHODS)
    local method_set = lookup(methods, string.upper)
    local allowed_headers = as_list(options.allowed_headers or options.headers, DEFAULT_HEADERS)
    local header_set = lookup(allowed_headers, string.lower)
    local methods_value = safe_join(methods, "methods")
    local headers_value = safe_join(allowed_headers, "allowed_headers")
    local expose = as_list(options.expose_headers, {})
    local expose_value = #expose > 0 and safe_join(expose, "expose_headers") or nil
    local max_age = options.max_age
    if max_age ~= nil then
        assert(type(max_age) == "number" and max_age >= 0, "CORS max_age must be a non-negative number")
        max_age = tostring(math.floor(max_age))
    end

    return function(ctx, next)
        local origin = ctx:get_header("origin")
        if not wildcard then add_vary(ctx, "Origin") end
        if type(origin) ~= "string" or origin == "" then return next() end

        local request_method = ctx:get_header("access-control-request-method")
        local preflight = ctx.method == "OPTIONS" and request_method ~= nil
        local allowed = Response.is_safe_header_value(origin) and matches(origin, ctx) == true

        if not allowed then
            if preflight or options.block then return forbidden(ctx, "origin not allowed", "cors_origin_not_allowed") end
            return next()
        end

        ctx:header("Access-Control-Allow-Origin", (wildcard and not options.credentials) and "*" or origin)
        if options.credentials then ctx:header("Access-Control-Allow-Credentials", "true") end

        if not preflight then
            if expose_value then ctx:header("Access-Control-Expose-Headers", expose_value) end
            return next()
        end

        if not method_set[request_method] then
            return forbidden(ctx, "method not allowed by CORS policy", "cors_method_not_allowed")
        end
        local requested = ctx:get_header("access-control-request-headers")
        if type(requested) == "string" then
            for name in requested:gmatch("[^,]+") do
                name = trim(name):lower()
                if name ~= "" and not header_set[name] and not SAFELISTED[name] then
                    return forbidden(ctx, "header not allowed by CORS policy", "cors_header_not_allowed")
                end
            end
        end
        if not wildcard then add_vary(ctx, "Access-Control-Request-Method, Access-Control-Request-Headers") end
        ctx:header("Access-Control-Allow-Methods", methods_value)
        ctx:header("Access-Control-Allow-Headers", headers_value)
        if max_age then ctx:header("Access-Control-Max-Age", max_age) end
        return ctx:no_content()
    end
end

-- Permissive policy for local development.
function Cors.default()
    return Cors.create({ origins = "*" })
end

-- Production policy: explicit origins, credentials, cached preflights and
-- 403 for requests from any other origin.
function Cors.strict(origins, options)
    local merged = { origins = origins, credentials = true, max_age = 86400, block = true }
    for key, value in pairs(options or {}) do merged[key] = value end
    return Cors.create(merged)
end

return Cors
