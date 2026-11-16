-- Authentication middleware: Bearer, Basic, API key and JWT.
--
-- Every middleware stores the authenticated principal in `ctx.state.user`
-- and responds 401 without calling `next` when authentication fails. With
-- `{ optional = true }` missing or invalid credentials are not an error:
-- the request continues, simply without `ctx.state.user`.
--
-- Middleware registered with `app:use` is global; protect a single route with
--   app:get("/me", auth.protect(auth.jwt(), action))
local Env = require("crescent.env")
local JWT = require("crescent.security.jwt")
local Base64 = require("crescent.security.base64")
local Crypto = require("crescent.security.crypto")

local Auth = {}

Auth.MAX_CREDENTIAL_LENGTH = 8192

local function oversized(value)
    return type(value) == "string" and #value > Auth.MAX_CREDENTIAL_LENGTH
end

local function check_validator(validator)
    if type(validator) ~= "function" then error("validator must be a function", 3) end
end

local function quoted_safe(value, name)
    if type(value) ~= "string" or value:find('[%c"\\]') then
        error(name .. " must be a string without quotes, backslashes or control characters", 3)
    end
    return value
end

-- Shared failure path: optional middleware continue, the others answer 401.
local function rejecter(options, challenge)
    return function(ctx, next, message, code, challenge_value)
        if options.optional then return next() end
        local header = challenge_value or challenge
        if header then ctx:header("WWW-Authenticate", header) end
        return ctx:error(401, message, nil, code)
    end
end

local function accept(ctx, next, user)
    ctx.state.user = user
    return next()
end

-- validator(token, ctx) -> ok, user_or_error
function Auth.bearer(validator, options)
    check_validator(validator)
    options = options or {}
    local reject = rejecter(options, "Bearer")
    return function(ctx, next)
        local raw = ctx:get_header("authorization")
        if oversized(raw) then return reject(ctx, next, "authorization header too large", "credentials_too_large") end
        local token = ctx:get_bearer()
        if not token then return reject(ctx, next, "missing or invalid authorization header", "missing_credentials") end
        local ok, user_or_error = validator(token, ctx)
        if not ok then
            return reject(ctx, next, user_or_error or "unauthorized", "invalid_credentials", 'Bearer error="invalid_token"')
        end
        return accept(ctx, next, user_or_error)
    end
end

-- validator(username, password, ctx) -> ok, user_or_error
-- The password may contain ':' (only the first ':' separates the fields).
function Auth.basic(validator, options)
    check_validator(validator)
    options = options or {}
    local challenge = 'Basic realm="' .. quoted_safe(options.realm or "Access", "realm") .. '", charset="UTF-8"'
    local reject = rejecter(options, challenge)
    return function(ctx, next)
        local header = ctx:get_header("authorization")
        if not header then return reject(ctx, next, "missing authorization header", "missing_credentials") end
        if oversized(header) then return reject(ctx, next, "authorization header too large", "credentials_too_large") end
        local encoded = type(header) == "string" and header:match("^[Bb][Aa][Ss][Ii][Cc]%s+(%S+)%s*$")
        if not encoded then return reject(ctx, next, "invalid authorization scheme", "invalid_credentials") end
        local decoded = Base64.decode(encoded)
        local username, password
        if decoded then username, password = decoded:match("^([^:]+):(.*)$") end
        if not username then return reject(ctx, next, "invalid credentials format", "invalid_credentials") end
        local ok, user_or_error = validator(username, password, ctx)
        if not ok then return reject(ctx, next, user_or_error or "invalid credentials", "invalid_credentials") end
        return accept(ctx, next, user_or_error)
    end
end

-- api_key([header], validator, [options]); validator(key, ctx) -> ok, user_or_error
function Auth.api_key(header_name, validator, options)
    if type(header_name) == "function" then
        header_name, validator, options = nil, header_name, validator
    end
    header_name = header_name or "x-api-key"
    check_validator(validator)
    options = options or {}
    local reject = rejecter(options)
    return function(ctx, next)
        local key = ctx:get_header(header_name)
        if type(key) ~= "string" or key == "" then return reject(ctx, next, "missing api key", "missing_credentials") end
        if oversized(key) then return reject(ctx, next, "api key too large", "credentials_too_large") end
        local ok, user_or_error = validator(key, ctx)
        if not ok then return reject(ctx, next, user_or_error or "invalid api key", "invalid_credentials") end
        return accept(ctx, next, user_or_error)
    end
end

-- HS256 keys shorter than the hash output (32 bytes) are brute-forceable
-- offline from any issued token (RFC 7518 §3.2).
Auth.MIN_SECRET_LENGTH = 32

local function resolve_secret(options)
    local secret = options.secret or Env.get("JWT_SECRET")
    if type(secret) ~= "string" or secret == "" then
        error("JWT secret is required: set JWT_SECRET or pass { secret = ... }", 3)
    end
    if #secret < Auth.MIN_SECRET_LENGTH and not options.allow_weak_secret then
        error(string.format(
            "JWT secret must be at least %d bytes (got %d); generate one with: openssl rand -base64 48",
            Auth.MIN_SECRET_LENGTH, #secret), 3)
    end
    return secret
end

local JWT_FAILURES = {
    token_expired = "token expired",
    token_revoked = "token revoked",
}

-- options: secret (default JWT_SECRET), issuer, audience, algorithms
-- (default { "HS256" }), leeway, revocation (store or false), optional,
-- get_user(payload, ctx) -> user | nil, token_type (default "access", so
-- refresh tokens are rejected).
function Auth.jwt(options)
    options = options or {}
    local secret = resolve_secret(options)
    local algorithms = options.algorithms or { "HS256" }
    assert(type(algorithms) == "table" and #algorithms > 0, "algorithms must be a non-empty list")
    for _, name in ipairs(algorithms) do
        if not JWT.supported_algorithm(name) then error("unsupported JWT algorithm: " .. tostring(name), 2) end
    end
    if options.get_user ~= nil and type(options.get_user) ~= "function" then
        error("get_user must be a function", 2)
    end
    local verify_options = {
        issuer = options.issuer,
        audience = options.audience,
        algorithms = algorithms,
        leeway = options.leeway,
        revocation = options.revocation,
        token_type = options.token_type or "access",
    }
    local reject = rejecter(options, "Bearer")
    local invalid_challenge = 'Bearer error="invalid_token"'

    return function(ctx, next)
        if oversized(ctx:get_header("authorization")) then
            return reject(ctx, next, "authorization header too large", "credentials_too_large")
        end
        local token = ctx:get_bearer()
        if not token then return reject(ctx, next, "missing or invalid authorization header", "missing_credentials") end
        local ok, payload, code = JWT.verify(token, secret, verify_options)
        if not ok then
            local message = JWT_FAILURES[code]
            return reject(ctx, next, message or "invalid token", message and code or "invalid_token", invalid_challenge)
        end
        local user = payload
        if options.get_user then
            user = options.get_user(payload, ctx)
            if user == nil then return reject(ctx, next, "invalid token", "invalid_token", invalid_challenge) end
        end
        ctx.state.jwt = payload
        return accept(ctx, next, user)
    end
end

Auth.protected = Auth.jwt

-- Wraps a single action with one middleware or a list of them, for
-- route-level protection: app:get("/me", auth.protect(auth.jwt(), action)).
function Auth.protect(middleware, action)
    if type(middleware) == "function" then middleware = { middleware } end
    assert(type(middleware) == "table" and #middleware > 0, "protect requires a middleware or a list of them")
    assert(type(action) == "function", "protect requires an action")
    for _, item in ipairs(middleware) do assert(type(item) == "function", "middleware must be a function") end
    return function(ctx)
        local function run(index)
            if index > #middleware then return action(ctx) end
            return middleware[index](ctx, function() return run(index + 1) end)
        end
        return run(1)
    end
end

-- Token helpers -----------------------------------------------------------

local function sign_options(options, extra)
    local result = {
        issuer = options.issuer,
        audience = options.audience,
        algorithm = options.algorithm,
        subject = options.subject,
    }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

function Auth.generate_token(payload, options)
    options = options or {}
    return JWT.sign(payload, resolve_secret(options), sign_options(options, {
        expires_in = options.expires_in,
        not_before = options.not_before,
        jti = options.jti,
    }))
end

function Auth.generate_access_token(payload, options)
    options = options or {}
    return JWT.create_access_token(payload, resolve_secret(options),
        sign_options(options, { expires_in = options.expires_in }))
end

-- `user` may be an id (number/string) or a table with `user_id` or `id`.
-- options: secret, access_expires_in, refresh_expires_in, issuer, audience,
-- algorithm, claims (extra claims copied into both tokens).
function Auth.generate_token_pair(user, options)
    options = options or {}
    local secret = resolve_secret(options)
    local access_ttl = options.access_expires_in or JWT.ACCESS_TOKEN_TTL
    local refresh_ttl = options.refresh_expires_in or JWT.REFRESH_TOKEN_TTL

    local payload
    if type(user) == "number" or type(user) == "string" then
        payload = { user_id = user }
    elseif type(user) == "table" then
        payload = { user_id = user.user_id or user.id, name = user.name, email = user.email }
    else
        error("user must be an id or a table", 2)
    end
    if payload.user_id == nil then error("user has no id", 2) end
    for key, value in pairs(options.claims or {}) do payload[key] = value end

    return {
        access_token = JWT.create_access_token(payload, secret, sign_options(options, { expires_in = access_ttl })),
        refresh_token = JWT.create_refresh_token(payload, secret, sign_options(options, { expires_in = refresh_ttl })),
        token_type = "Bearer",
        expires_in = access_ttl,
        refresh_expires_in = refresh_ttl,
    }
end

-- Same options as jwt.verify plus `secret` (default JWT_SECRET).
function Auth.verify_token(token, options)
    options = options or {}
    local secret = resolve_secret(options)
    return JWT.verify(token, secret, options)
end

-- Accepts only refresh tokens; use it in the token refresh endpoint.
function Auth.verify_refresh_token(token, options)
    local merged = {}
    for key, value in pairs(options or {}) do merged[key] = value end
    merged.token_type = "refresh"
    return Auth.verify_token(token, merged)
end

function Auth.decode_token(token)
    return JWT.decode(token)
end

function Auth.revoke_token(payload_or_jti, exp)
    return JWT.revoke(payload_or_jti, exp)
end

Auth.secure_compare = Crypto.secure_compare

return Auth
