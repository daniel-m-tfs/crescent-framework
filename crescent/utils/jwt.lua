-- crescent/utils/jwt.lua
-- JWT HS256 (HMAC-SHA256) - self-contained for Luvit (no ngx, no cjson, no downloads)
-- API:
--   jwt.sign(payload, secret, options) -> token
--   jwt.verify(token, secret, options) -> true, payload | false, err
--   jwt.decode(token) -> header, payload (no signature check)
--   jwt.create_access_token(payload, secret, expiresIn?)
--   jwt.create_refresh_token(payload, secret, expiresIn?)

local M = {}

-- ------------------------------------------------------------
-- bit ops (LuaJIT/Luvit) — necessário para constant_time_equals
-- ------------------------------------------------------------
local bit
do
  local ok, b = pcall(require, "bit")
  if ok then bit = b end
  if not bit then
    ok, b = pcall(require, "bit32")
    if ok then bit = b end
  end
end

assert(bit, "bit/bit32 is required (LuaJIT/Luvit should provide it)")

local bor, bxor = bit.bor, bit.bxor

-- ------------------------------------------------------------
-- minimal JSON (uses Luvit json if available; fallback otherwise)
-- ------------------------------------------------------------
local json
do
  local ok, j = pcall(require, "json") -- Luvit typically has this
  if ok and j then
    json = j
  end
end

if not json then
  json = require("crescent.utils.json_fallback")
end

-- ------------------------------------------------------------
-- Base64 / Base64URL
-- ------------------------------------------------------------
local base64 = require("crescent.utils.base64")
local base64url_encode = base64.url_encode
local base64url_decode = base64.url_decode

-- ------------------------------------------------------------
-- HMAC-SHA256 — openssl nativo quando disponível (mesma dependência hard
-- que crescent/utils/hash.lua já exige), fallback pure-Lua senão
-- ------------------------------------------------------------
local openssl_hmac
do
  local ok, openssl = pcall(require, "openssl")
  if ok and openssl and openssl.hmac then
    openssl_hmac = openssl.hmac
  end
end

local sha256_fallback -- lazy: só carrega o SHA-256 pure-Lua se openssl faltar

local function hmac_sha256(key, message)
  if openssl_hmac then
    local ok, sig = pcall(openssl_hmac.digest, "sha256", message, key, true)
    if ok and sig then return sig end
  end

  sha256_fallback = sha256_fallback or require("crescent.utils.sha256_fallback")
  return sha256_fallback.hmac_sha256(key, message)
end

-- ------------------------------------------------------------
-- constant-time compare
-- ------------------------------------------------------------
local function constant_time_equals(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local la, lb = #a, #b
  local diff = bxor(la, lb)
  local n = math.max(la, lb)
  for i = 1, n do
    local ca = a:byte(i) or 0
    local cb = b:byte(i) or 0
    diff = bor(diff, bxor(ca, cb))
  end
  return diff == 0
end

-- ------------------------------------------------------------
-- helpers
-- ------------------------------------------------------------
local function split3(token)
  local a, b, c = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
  return a, b, c
end

local function shallow_copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function now_sec(options)
  if options and type(options.now) == "function" then
    return options.now()
  end
  return os.time()
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------
function M.sign(payload, secret, options)
  if type(payload) ~= "table" then error("payload must be a table") end
  if type(secret) ~= "string" or secret == "" then error("secret is required") end
  options = options or {}

  local p = shallow_copy(payload)
  local now = now_sec(options)

  if options.expiresIn then p.exp = now + options.expiresIn end
  if options.notBefore then p.nbf = now + options.notBefore end
  if options.issuer then p.iss = options.issuer end
  if options.audience then p.aud = options.audience end
  if p.iat == nil then p.iat = now end

  local header = { alg = "HS256", typ = "JWT" }

  local header_b64 = base64url_encode(json.encode(header))
  local payload_b64 = base64url_encode(json.encode(p))
  local message = header_b64 .. "." .. payload_b64

  local sig = hmac_sha256(secret, message)
  local sig_b64 = base64url_encode(sig)

  return message .. "." .. sig_b64
end

function M.verify(token, secret, options)
  if type(token) ~= "string" or token == "" then return false, "token is required" end
  if type(secret) ~= "string" or secret == "" then return false, "secret is required" end
  options = options or {}

  local h64, p64, s64 = split3(token)
  if not h64 then return false, "invalid token format" end

  local header_json = base64url_decode(h64)
  local payload_json = base64url_decode(p64)
  local sig = base64url_decode(s64)
  if not header_json then return false, "invalid header encoding" end
  if not payload_json then return false, "invalid payload encoding" end
  if not sig then return false, "invalid signature encoding" end

  local ok, header = pcall(json.decode, header_json)
  if not ok or type(header) ~= "table" then return false, "invalid header json" end

  if header.alg ~= "HS256" then
    return false, "unsupported algorithm: " .. tostring(header.alg)
  end

  local payload
  ok, payload = pcall(json.decode, payload_json)
  if not ok or type(payload) ~= "table" then return false, "invalid payload json" end

  local message = h64 .. "." .. p64
  local expected = hmac_sha256(secret, message)
  if not constant_time_equals(sig, expected) then
    return false, "invalid signature"
  end

  local leeway = tonumber(options.leeway or 0) or 0
  local now = now_sec(options)

  if payload.exp and type(payload.exp) == "number" and (payload.exp + leeway) < now then
    return false, "token expired"
  end
  if payload.nbf and type(payload.nbf) == "number" and (payload.nbf - leeway) > now then
    return false, "token not yet valid"
  end

  if options.issuer and payload.iss ~= options.issuer then
    return false, "invalid issuer"
  end

  if options.audience then
    local aud = payload.aud
    if type(aud) == "table" then
      local found = false
      for _, v in ipairs(aud) do
        if v == options.audience then found = true; break end
      end
      if not found then return false, "invalid audience" end
    elseif aud ~= options.audience then
      return false, "invalid audience"
    end
  end

  return true, payload
end

function M.decode(token)
  if type(token) ~= "string" or token == "" then return nil, nil end
  local h64, p64 = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
  if not h64 then return nil, nil end

  local header_json = base64url_decode(h64)
  local payload_json = base64url_decode(p64)
  if not header_json or not payload_json then return nil, nil end

  local ok1, header = pcall(json.decode, header_json)
  local ok2, payload = pcall(json.decode, payload_json)
  if not ok1 or not ok2 then return nil, nil end
  return header, payload
end

function M.create_refresh_token(payload, secret, expiresIn)
  expiresIn = expiresIn or (30 * 24 * 60 * 60)
  return M.sign(payload, secret, { expiresIn = expiresIn })
end

function M.create_access_token(payload, secret, expiresIn)
  expiresIn = expiresIn or (15 * 60)
  return M.sign(payload, secret, { expiresIn = expiresIn })
end

return M
