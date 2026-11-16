-- JSON Web Tokens signed with HMAC (HS256, HS384, HS512).
--
--   jwt.sign(payload, secret, options) -> token
--   jwt.verify(token, secret, options) -> true, payload | false, message, code
--   jwt.decode(token)                  -> header, payload (NO signature check)
--
-- `verify` only accepts the algorithms listed in `options.algorithms`
-- (default { "HS256" }); "none" and asymmetric algorithms are never accepted.
-- Revocation is checked against a store shared by every nginx worker.
local json = require("crescent.json")
local Base64 = require("crescent.security.base64")
local Crypto = require("crescent.security.crypto")

local JWT = {}

local DIGESTS = { HS256 = "sha256", HS384 = "sha384", HS512 = "sha512" }
local DEFAULT_ALGORITHMS = { "HS256" }

JWT.ACCESS_TOKEN_TTL = 15 * 60
JWT.REFRESH_TOKEN_TTL = 30 * 24 * 60 * 60

local function fail(message, code)
    return false, message, code
end

local function now_from(options)
    if type(options.now) == "function" then return options.now() end
    return Crypto.now()
end

local function copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

function JWT.supported_algorithm(name)
    return DIGESTS[name] ~= nil
end

-- Revocation stores implement `revoke(jti, ttl)`, `is_revoked(jti)` and
-- `unrevoke(jti)`. The default keeps entries in an ngx.shared dict, so a
-- token revoked in one worker is rejected by all of them; each entry expires
-- when the token itself would have, keeping the dict bounded.
-- Without a dict name it prefers a dedicated `crescent_jwt` dict (so rate
-- limit counters can never push revocations out) and falls back to
-- `crescent_limits`.
function JWT.shared_store(dict_name, prefix)
    prefix = prefix or "jwt:revoked:"
    local function dict()
        local shared = ngx and ngx.shared
        local selected = shared and (dict_name and shared[dict_name] or shared.crescent_jwt or shared.crescent_limits)
        if not selected then
            error("JWT revocation store requires `lua_shared_dict " .. (dict_name or "crescent_jwt") .. "` in nginx.conf", 3)
        end
        return selected
    end
    return {
        revoke = function(jti, ttl)
            -- safe_set fails instead of evicting other live entries when full.
            local ok, err = dict():safe_set(prefix .. jti, true, ttl or 0)
            if not ok then error("unable to revoke token: " .. tostring(err), 2) end
        end,
        is_revoked = function(jti)
            return dict():get(prefix .. jti) == true
        end,
        unrevoke = function(jti)
            dict():delete(prefix .. jti)
        end,
    }
end

local default_store = JWT.shared_store()

function JWT.set_revocation_store(store)
    assert(type(store) == "table" and type(store.is_revoked) == "function" and type(store.revoke) == "function",
        "revocation store must implement revoke(jti, ttl) and is_revoked(jti)")
    default_store = store
end

function JWT.revocation_store()
    return default_store
end

-- Accepts a jti plus the token's `exp`, or a verified payload table.
function JWT.revoke(jti, exp, store)
    if type(jti) == "table" then jti, exp = jti.jti, jti.exp end
    if type(jti) ~= "string" or jti == "" then error("jti must be a non-empty string", 2) end
    local ttl = 0
    if type(exp) == "number" then
        ttl = exp - Crypto.now()
        if ttl <= 0 then return true end
    end
    (store or default_store).revoke(jti, ttl)
    return true
end

function JWT.unrevoke(jti, store)
    local selected = store or default_store
    if selected.unrevoke then selected.unrevoke(jti) end
end

function JWT.sign(payload, secret, options)
    if type(payload) ~= "table" then error("payload must be a table", 2) end
    if type(secret) ~= "string" or secret == "" then error("secret is required", 2) end
    options = options or {}
    local algorithm = options.algorithm or "HS256"
    local digest = DIGESTS[algorithm]
    if not digest then error("unsupported algorithm: " .. tostring(algorithm), 2) end

    local claims = copy(payload)
    local now = now_from(options)
    if options.expires_in then claims.exp = now + options.expires_in end
    if options.not_before then claims.nbf = now + options.not_before end
    if options.issuer then claims.iss = options.issuer end
    if options.audience then claims.aud = options.audience end
    if options.subject then claims.sub = options.subject end
    if options.type then claims.typ = options.type end
    if claims.iat == nil then claims.iat = now end
    if claims.jti == nil and options.jti ~= false then claims.jti = Crypto.random_hex(16) end

    local header_json = assert(json.encode({ alg = algorithm, typ = "JWT" }))
    local payload_json, encode_error = json.encode(claims)
    if not payload_json then error("unable to encode payload: " .. tostring(encode_error), 2) end
    local message = Base64.url_encode(header_json) .. "." .. Base64.url_encode(payload_json)
    return message .. "." .. Base64.url_encode(Crypto.hmac(digest, secret, message))
end

local function decode_part(part)
    local text = Base64.url_decode(part)
    if not text then return nil end
    local value = json.decode(text)
    if type(value) ~= "table" then return nil end
    return value
end

function JWT.decode(token)
    if type(token) ~= "string" then return nil, nil end
    local header_part, payload_part = token:match("^([^.]+)%.([^.]+)%.[^.]+$")
    if not header_part then return nil, nil end
    local header, payload = decode_part(header_part), decode_part(payload_part)
    if not header or not payload then return nil, nil end
    return header, payload
end

local function audience_matches(claim, expected)
    local accepted = type(expected) == "table" and expected or { expected }
    local present = type(claim) == "table" and claim or { claim }
    for _, value in ipairs(present) do
        if type(value) == "string" and contains(accepted, value) then return true end
    end
    return false
end

local function check_claims(payload, options)
    local leeway = tonumber(options.leeway or 0)
    if not leeway or leeway < 0 or leeway ~= leeway or leeway == math.huge then
        return fail("invalid leeway", "invalid_options")
    end
    if payload.exp ~= nil and type(payload.exp) ~= "number" then
        return fail("invalid expiration claim", "invalid_claim")
    end
    if payload.nbf ~= nil and type(payload.nbf) ~= "number" then
        return fail("invalid not-before claim", "invalid_claim")
    end
    if payload.iat ~= nil and type(payload.iat) ~= "number" then
        return fail("invalid issued-at claim", "invalid_claim")
    end
    local now = now_from(options)
    if payload.exp and payload.exp + leeway <= now then return fail("token expired", "token_expired") end
    if payload.nbf and payload.nbf - leeway > now then return fail("token not yet valid", "token_not_yet_valid") end
    if options.require_exp and payload.exp == nil then return fail("missing expiration claim", "invalid_claim") end
    if options.issuer and payload.iss ~= options.issuer then return fail("invalid issuer", "invalid_issuer") end
    if options.audience and not audience_matches(payload.aud, options.audience) then
        return fail("invalid audience", "invalid_audience")
    end
    -- token_type = "access" rejects refresh tokens (typ = "refresh");
    -- token_type = "refresh" accepts only refresh tokens.
    if options.token_type == "refresh" and payload.typ ~= "refresh" then
        return fail("refresh token required", "invalid_token_type")
    elseif options.token_type == "access" and payload.typ ~= nil and payload.typ ~= "access" then
        return fail("access token required", "invalid_token_type")
    end
    return true
end

function JWT.verify(token, secret, options)
    if type(token) ~= "string" or token == "" then return fail("token is required", "invalid_token") end
    if type(secret) ~= "string" or secret == "" then return fail("secret is required", "invalid_options") end
    options = options or {}

    local header_part, payload_part, signature_part = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
    if not header_part then return fail("invalid token format", "invalid_token") end

    local header = decode_part(header_part)
    if not header then return fail("invalid header", "invalid_token") end
    local algorithm = header.alg
    local allowed = options.algorithms or DEFAULT_ALGORITHMS
    if type(algorithm) ~= "string" or not DIGESTS[algorithm] or not contains(allowed, algorithm) then
        return fail("unsupported algorithm: " .. tostring(algorithm), "unsupported_algorithm")
    end

    -- Comparing the encoded form also rejects non-canonical base64url
    -- variants of a valid signature.
    local message = header_part .. "." .. payload_part
    local expected = Base64.url_encode(Crypto.hmac(DIGESTS[algorithm], secret, message))
    if not Crypto.secure_compare(signature_part, expected) then
        return fail("invalid signature", "invalid_signature")
    end

    local payload = decode_part(payload_part)
    if not payload then return fail("invalid payload", "invalid_token") end

    local valid, message_text, code = check_claims(payload, options)
    if not valid then return false, message_text, code end

    local store = options.revocation
    if store == nil then store = default_store end
    if store and payload.jti ~= nil then
        if type(payload.jti) ~= "string" then return fail("invalid token id", "invalid_claim") end
        if store.is_revoked(payload.jti, payload) then return fail("token revoked", "token_revoked") end
    end
    return true, payload
end

-- `options` may be a number (expires_in, as in the original API) or a table
-- of sign options.
local function token_options(options, default_ttl, token_type)
    if type(options) == "number" then options = { expires_in = options } end
    local result = copy(options or {})
    result.expires_in = result.expires_in or default_ttl
    result.type = token_type
    return result
end

function JWT.create_access_token(payload, secret, options)
    return JWT.sign(payload, secret, token_options(options, JWT.ACCESS_TOKEN_TTL, "access"))
end

function JWT.create_refresh_token(payload, secret, options)
    return JWT.sign(payload, secret, token_options(options, JWT.REFRESH_TOKEN_TTL, "refresh"))
end

return JWT
