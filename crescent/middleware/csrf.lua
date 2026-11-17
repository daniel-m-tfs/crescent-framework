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
--
-- BREACH: the session keeps a 32-byte secret that never appears in a
-- response. Each request gets a masked token, base64url(mask .. mask XOR
-- secret) with a fresh random mask, so compressed pages never repeat the
-- secret's bytes. Any masked token of the current secret is accepted.
-- session:regenerate() (login) drops the secret, so a new one is issued.
local bit = require("bit")
local Crypto = require("crescent.security.crypto")
local Base64 = require("crescent.security.base64")

local bxor, byte, char = bit.bxor, string.byte, string.char

local Csrf = {}

local SESSION_KEY = "_csrf_token"
local SECRET_SIZE = 32
-- base64url of 2 * SECRET_SIZE bytes, unpadded.
local MASKED_LENGTH = 86
local DEFAULT_SAFE_METHODS = { "GET", "HEAD", "OPTIONS", "TRACE" }

Csrf.SESSION_KEY = SESSION_KEY

local function require_session(ctx)
    if not ctx.session then
        error("CSRF protection requires the session middleware: "
            .. "app:use(session.middleware(...)) must come before csrf.create()", 3)
    end
    return ctx.session
end

local function xor(left, right)
    local bytes = {}
    for index = 1, #left do bytes[index] = char(bxor(byte(left, index), byte(right, index))) end
    return table.concat(bytes)
end

-- The session's raw secret, or nil when it is missing or malformed.
local function session_secret(session)
    local stored = session:get(SESSION_KEY)
    local secret = type(stored) == "string" and Base64.url_decode(stored)
    if secret and #secret == SECRET_SIZE then return secret end
    return nil
end

function Csrf.mask(secret)
    local mask = Crypto.random_bytes(SECRET_SIZE)
    return Base64.url_encode(mask .. xor(mask, secret))
end

-- Raw secret carried by a masked token, or nil.
function Csrf.unmask(token)
    if type(token) ~= "string" or #token ~= MASKED_LENGTH then return nil end
    local raw = Base64.url_decode(token)
    if not raw or #raw ~= 2 * SECRET_SIZE then return nil end
    return xor(raw:sub(1, SECRET_SIZE), raw:sub(SECRET_SIZE + 1))
end

-- Returns a masked token for this request (the same one for every call in
-- the request), creating the session secret on first use.
function Csrf.token(ctx)
    local session = require_session(ctx)
    local secret = session_secret(session)
    if not secret then
        secret = Crypto.random_bytes(SECRET_SIZE)
        session:set(SESSION_KEY, Base64.url_encode(secret))
    end
    local cached = ctx._csrf_masked
    if cached and cached.secret == secret then return cached.token end
    local token = Csrf.mask(secret)
    ctx._csrf_masked = { secret = secret, token = token }
    return token
end

function Csrf.valid(ctx, token)
    local secret = session_secret(require_session(ctx))
    local given = Csrf.unmask(token)
    return secret ~= nil and given ~= nil and Crypto.secure_compare(given, secret)
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
        require_session(ctx)
        ctx._csrf_field = field
        if safe[ctx.method] or (skip and skip(ctx)) then return next() end
        if not Csrf.valid(ctx, submitted_token(ctx, field, header)) then
            return ctx:error(403, "invalid CSRF token", nil, "csrf_invalid")
        end
        return next()
    end
end

return Csrf
