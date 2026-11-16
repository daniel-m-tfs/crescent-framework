-- CSRF protection with a synchronizer token kept in the session.
--
--   app:use(session.middleware())
--   app:use(csrf.create({
--       skip = function(ctx) return ctx:get_bearer() ~= nil end,  -- e.g. token-authenticated APIs
--       safe_methods = { "GET", "HEAD", "OPTIONS", "TRACE" },
--       field = "_csrf",               -- form field
--       header = "X-CSRF-Token",       -- header (AJAX)
--   }))
--
-- Unsafe requests (POST, PUT, PATCH, DELETE...) must echo the token from
-- `ctx:csrf_token()` (or `<%- csrf_field() %>` in views); otherwise they get
-- 403 `csrf_invalid`.
local Crypto = require("crescent.security.crypto")
local Base64 = require("crescent.security.base64")

local Csrf = {}

local SESSION_KEY = "_csrf_token"
local DEFAULT_SAFE_METHODS = { "GET", "HEAD", "OPTIONS", "TRACE" }

local function require_session(ctx)
    if not ctx.session then
        error("CSRF protection requires the session middleware: "
            .. "app:use(session.middleware(...)) must come before csrf.create()", 3)
    end
    return ctx.session
end

-- Returns the session's token, creating it on first use.
function Csrf.token(ctx)
    local session = require_session(ctx)
    local token = session:get(SESSION_KEY)
    if type(token) ~= "string" then
        token = Base64.url_encode(Crypto.random_bytes(32))
        session:set(SESSION_KEY, token)
    end
    return token
end

local function escape_attribute(value)
    return (value:gsub("[&<>\"']", {
        ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;",
    }))
end

function Csrf.field(ctx, name)
    return string.format('<input type="hidden" name="%s" value="%s">',
        escape_attribute(name or ctx._csrf_field or "_csrf"), escape_attribute(Csrf.token(ctx)))
end

local function submitted_token(ctx, field, header)
    local value = ctx:get_header(header)
    if type(value) == "string" and value ~= "" then return value end
    if type(ctx.body) == "table" then
        value = ctx.body[field]
        if type(value) == "string" then return value end
    end
    return nil
end

function Csrf.create(options)
    options = options or {}
    local safe = {}
    for _, method in ipairs(options.safe_methods or DEFAULT_SAFE_METHODS) do safe[method:upper()] = true end
    local field = options.field or "_csrf"
    local header = (options.header or "X-CSRF-Token"):lower()
    local skip = options.skip
    assert(skip == nil or type(skip) == "function", "csrf skip must be a function")

    return function(ctx, next)
        local session = require_session(ctx)
        ctx._csrf_field = field
        if safe[ctx.method] or (skip and skip(ctx)) then return next() end
        local expected = session:get(SESSION_KEY)
        local given = submitted_token(ctx, field, header)
        if type(expected) ~= "string" or not Crypto.secure_compare(given, expected) then
            return ctx:error(403, "invalid CSRF token", nil, "csrf_invalid")
        end
        return next()
    end
end

return Csrf
