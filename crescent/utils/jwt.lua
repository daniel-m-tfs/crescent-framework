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
-- bit ops (LuaJIT/Luvit)
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

local band, bor, bxor = bit.band, bit.bor, bit.bxor
local rshift, lshift = bit.rshift, bit.lshift
local bnot = bit.bnot
local tobit = bit.tobit or function(x) return x end

local function rotr(x, n)
  return bor(rshift(x, n), lshift(x, 32 - n))
end

local function add32(a, b)
  return tobit(a + b)
end

local function add32_4(a, b, c, d)
  return tobit(a + b + c + d)
end

local function add32_5(a, b, c, d, e)
  return tobit(a + b + c + d + e)
end

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

-- Fallback minimal JSON if require("json") is not available
if not json then
  json = {}

  local function is_array(t)
    local n = 0
    for k, _ in pairs(t) do
      if type(k) ~= "number" then return false end
      if k <= 0 or k % 1 ~= 0 then return false end
      if k > n then n = k end
    end
    for i = 1, n do
      if t[i] == nil then return false end
    end
    return true, n
  end

  local escapes = {
    ['"']  = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t',
  }

  local function escape_str(s)
    return s:gsub('[%z\1-\31\\"]', function(c)
      return escapes[c] or string.format("\\u%04x", c:byte())
    end)
  end

  function json.encode(v)
    local tv = type(v)
    if v == nil then return "null" end
    if tv == "boolean" then return v and "true" or "false" end
    if tv == "number" then
      if v ~= v or v == math.huge or v == -math.huge then
        error("invalid number in json")
      end
      return tostring(v)
    end
    if tv == "string" then
      return '"' .. escape_str(v) .. '"'
    end
    if tv == "table" then
      local arr, n = is_array(v)
      if arr then
        local out = {}
        for i = 1, n do out[i] = json.encode(v[i]) end
        return "[" .. table.concat(out, ",") .. "]"
      else
        local out = {}
        for k, val in pairs(v) do
          if type(k) ~= "string" then
            error("json object keys must be strings")
          end
          out[#out + 1] = json.encode(k) .. ":" .. json.encode(val)
        end
        return "{" .. table.concat(out, ",") .. "}"
      end
    end
    error("unsupported type in json: " .. tv)
  end

  -- JSON decoder (minimal, enough for JWT claims)
  local function decode_error(msg, s, i)
    error(msg .. " at position " .. tostring(i) .. " near '" .. s:sub(i, i + 20) .. "'")
  end

  local function skip_ws(s, i)
    while true do
      local c = s:byte(i)
      if not c then return i end
      if c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D then
        i = i + 1
      else
        return i
      end
    end
  end

  local function parse_literal(s, i, lit, val)
    if s:sub(i, i + #lit - 1) == lit then
      return val, i + #lit
    end
    decode_error("invalid literal", s, i)
  end

  local function codepoint_to_utf8(cp)
    if cp <= 0x7F then
      return string.char(cp)
    elseif cp <= 0x7FF then
      return string.char(0xC0 + rshift(cp, 6), 0x80 + band(cp, 0x3F))
    elseif cp <= 0xFFFF then
      return string.char(
        0xE0 + rshift(cp, 12),
        0x80 + band(rshift(cp, 6), 0x3F),
        0x80 + band(cp, 0x3F)
      )
    else
      return string.char(
        0xF0 + rshift(cp, 18),
        0x80 + band(rshift(cp, 12), 0x3F),
        0x80 + band(rshift(cp, 6), 0x3F),
        0x80 + band(cp, 0x3F)
      )
    end
  end

  local function parse_string(s, i)
    -- expects opening quote at i
    i = i + 1
    local out = {}
    local o = 1
    while true do
      local c = s:byte(i)
      if not c then decode_error("unterminated string", s, i) end
      if c == 0x22 then -- "
        return table.concat(out), i + 1
      elseif c == 0x5C then -- backslash
        local esc = s:byte(i + 1)
        if not esc then decode_error("bad escape", s, i) end
        if esc == 0x22 then out[o] = '"'; i = i + 2
        elseif esc == 0x5C then out[o] = "\\"; i = i + 2
        elseif esc == 0x2F then out[o] = "/"; i = i + 2
        elseif esc == 0x62 then out[o] = "\b"; i = i + 2
        elseif esc == 0x66 then out[o] = "\f"; i = i + 2
        elseif esc == 0x6E then out[o] = "\n"; i = i + 2
        elseif esc == 0x72 then out[o] = "\r"; i = i + 2
        elseif esc == 0x74 then out[o] = "\t"; i = i + 2
        elseif esc == 0x75 then
          local hex = s:sub(i + 2, i + 5)
          if #hex < 4 or not hex:match("^[0-9a-fA-F]+$") then
            decode_error("invalid unicode escape", s, i)
          end
          local cp = tonumber(hex, 16)
          i = i + 6
          -- handle surrogate pair
          if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
            local hex2 = s:sub(i + 2, i + 5)
            if #hex2 == 4 and hex2:match("^[0-9a-fA-F]+$") then
              local cp2 = tonumber(hex2, 16)
              if cp2 >= 0xDC00 and cp2 <= 0xDFFF then
                cp = 0x10000 + (cp - 0xD800) * 0x400 + (cp2 - 0xDC00)
                i = i + 6
              end
            end
          end
          out[o] = codepoint_to_utf8(cp)
        else
          decode_error("invalid escape char", s, i)
        end
        o = o + 1
      else
        out[o] = string.char(c)
        o = o + 1
        i = i + 1
      end
    end
  end

  local function parse_number(s, i)
    local start = i
    local c = s:sub(i, i)
    if c == "-" then i = i + 1 end
    if s:sub(i, i) == "0" then
      i = i + 1
    else
      if not s:sub(i, i):match("%d") then decode_error("invalid number", s, i) end
      while s:sub(i, i):match("%d") do i = i + 1 end
    end
    if s:sub(i, i) == "." then
      i = i + 1
      if not s:sub(i, i):match("%d") then decode_error("invalid number fraction", s, i) end
      while s:sub(i, i):match("%d") do i = i + 1 end
    end
    local e = s:sub(i, i)
    if e == "e" or e == "E" then
      i = i + 1
      local sign = s:sub(i, i)
      if sign == "+" or sign == "-" then i = i + 1 end
      if not s:sub(i, i):match("%d") then decode_error("invalid exponent", s, i) end
      while s:sub(i, i):match("%d") do i = i + 1 end
    end
    local num = tonumber(s:sub(start, i - 1))
    if num == nil then decode_error("invalid number", s, start) end
    return num, i
  end

  local parse_value

  local function parse_array(s, i)
    i = i + 1 -- skip [
    local arr = {}
    i = skip_ws(s, i)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    local idx = 1
    while true do
      local v; v, i = parse_value(s, i)
      arr[idx] = v; idx = idx + 1
      i = skip_ws(s, i)
      local c = s:sub(i, i)
      if c == "]" then return arr, i + 1 end
      if c ~= "," then decode_error("expected ',' or ']'", s, i) end
      i = skip_ws(s, i + 1)
    end
  end

  local function parse_object(s, i)
    i = i + 1 -- skip {
    local obj = {}
    i = skip_ws(s, i)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      if s:sub(i, i) ~= '"' then decode_error("expected string key", s, i) end
      local k; k, i = parse_string(s, i)
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ":" then decode_error("expected ':'", s, i) end
      i = skip_ws(s, i + 1)
      local v; v, i = parse_value(s, i)
      obj[k] = v
      i = skip_ws(s, i)
      local c = s:sub(i, i)
      if c == "}" then return obj, i + 1 end
      if c ~= "," then decode_error("expected ',' or '}'", s, i) end
      i = skip_ws(s, i + 1)
    end
  end

  parse_value = function(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == '"' then return parse_string(s, i) end
    if c == "{" then return parse_object(s, i) end
    if c == "[" then return parse_array(s, i) end
    if c == "t" then return parse_literal(s, i, "true", true) end
    if c == "f" then return parse_literal(s, i, "false", false) end
    if c == "n" then return parse_literal(s, i, "null", nil) end
    return parse_number(s, i)
  end

  function json.decode(s)
    local v, i = parse_value(s, 1)
    i = skip_ws(s, i)
    if i <= #s then decode_error("trailing garbage", s, i) end
    return v
  end
end

-- ------------------------------------------------------------
-- Base64 / Base64URL (pure Lua)
-- ------------------------------------------------------------
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64lookup = {}
for i = 1, #b64chars do
  b64lookup[b64chars:sub(i, i)] = i - 1
end
b64lookup["="] = 0

local function base64_encode(data)
  local out = {}
  local len = #data
  local i = 1
  while i <= len do
    local a = data:byte(i) or 0
    local b = data:byte(i + 1) or 0
    local c = data:byte(i + 2) or 0
    local triple = a * 65536 + b * 256 + c

    local s1 = math.floor(triple / 262144) % 64
    local s2 = math.floor(triple / 4096) % 64
    local s3 = math.floor(triple / 64) % 64
    local s4 = triple % 64

    out[#out + 1] = b64chars:sub(s1 + 1, s1 + 1)
    out[#out + 1] = b64chars:sub(s2 + 1, s2 + 1)

    if i + 1 <= len then
      out[#out + 1] = b64chars:sub(s3 + 1, s3 + 1)
    else
      out[#out + 1] = "="
    end

    if i + 2 <= len then
      out[#out + 1] = b64chars:sub(s4 + 1, s4 + 1)
    else
      out[#out + 1] = "="
    end

    i = i + 3
  end
  return table.concat(out)
end

local function base64_decode(data)
  data = data:gsub("%s", "")
  if (#data % 4) ~= 0 then return nil end

  local out = {}
  local i = 1
  while i <= #data do
    local c1 = b64lookup[data:sub(i, i)]
    local c2 = b64lookup[data:sub(i + 1, i + 1)]
    local c3 = b64lookup[data:sub(i + 2, i + 2)]
    local c4 = b64lookup[data:sub(i + 3, i + 3)]
    if c1 == nil or c2 == nil or c3 == nil or c4 == nil then return nil end

    local triple = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
    local a = math.floor(triple / 65536) % 256
    local b = math.floor(triple / 256) % 256
    local c = triple % 256

    out[#out + 1] = string.char(a)
    if data:sub(i + 2, i + 2) ~= "=" then out[#out + 1] = string.char(b) end
    if data:sub(i + 3, i + 3) ~= "=" then out[#out + 1] = string.char(c) end

    i = i + 4
  end
  return table.concat(out)
end

local function base64url_encode(raw)
  local b64 = base64_encode(raw)
  b64 = b64:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
  return b64
end

local function base64url_decode(s)
  s = s:gsub("%-", "+"):gsub("_", "/")
  local pad = #s % 4
  if pad == 2 then s = s .. "=="
  elseif pad == 3 then s = s .. "="
  elseif pad ~= 0 then return nil end
  return base64_decode(s)
end

-- ------------------------------------------------------------
-- SHA-256 (pure Lua)
-- ------------------------------------------------------------
local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
}

local function u32_to_be(n)
  local b1 = band(rshift(n, 24), 0xFF)
  local b2 = band(rshift(n, 16), 0xFF)
  local b3 = band(rshift(n, 8), 0xFF)
  local b4 = band(n, 0xFF)
  return string.char(b1, b2, b3, b4)
end

local function be_to_u32(s, i)
  local b1 = s:byte(i)     or 0
  local b2 = s:byte(i + 1) or 0
  local b3 = s:byte(i + 2) or 0
  local b4 = s:byte(i + 3) or 0
  return tobit(b1 * 16777216 + b2 * 65536 + b3 * 256 + b4)
end

local function sha256(raw)
  local h0 = 0x6a09e667
  local h1 = 0xbb67ae85
  local h2 = 0x3c6ef372
  local h3 = 0xa54ff53a
  local h4 = 0x510e527f
  local h5 = 0x9b05688c
  local h6 = 0x1f83d9ab
  local h7 = 0x5be0cd19

  local msg = raw
  local bit_len = #msg * 8

  -- padding: 0x80, then zeros, then 64-bit length
  msg = msg .. string.char(0x80)
  local pad_len = (56 - (#msg % 64)) % 64
  msg = msg .. string.rep("\0", pad_len)

  local hi = math.floor(bit_len / 2^32)
  local lo = bit_len % 2^32
  msg = msg .. u32_to_be(hi) .. u32_to_be(lo)

  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      w[i] = be_to_u32(msg, chunk + i * 4)
    end
    for i = 16, 63 do
      local s0 = bxor(rotr(w[i-15], 7), rotr(w[i-15], 18), rshift(w[i-15], 3))
      local s1 = bxor(rotr(w[i-2], 17), rotr(w[i-2], 19), rshift(w[i-2], 10))
      w[i] = add32_4(w[i-16], s0, w[i-7], s1)
    end

    local a,b,c,d,e,f,g,h = h0,h1,h2,h3,h4,h5,h6,h7

    for i = 0, 63 do
      local S1 = bxor(rotr(e, 6), rotr(e, 11), rotr(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local temp1 = add32_5(h, S1, ch, K[i+1], w[i])
      local S0 = bxor(rotr(a, 2), rotr(a, 13), rotr(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      local temp2 = add32(S0, maj)

      h = g
      g = f
      f = e
      e = add32(d, temp1)
      d = c
      c = b
      b = a
      a = add32(temp1, temp2)
    end

    h0 = add32(h0, a)
    h1 = add32(h1, b)
    h2 = add32(h2, c)
    h3 = add32(h3, d)
    h4 = add32(h4, e)
    h5 = add32(h5, f)
    h6 = add32(h6, g)
    h7 = add32(h7, h)
  end

  return u32_to_be(h0) .. u32_to_be(h1) .. u32_to_be(h2) .. u32_to_be(h3)
      .. u32_to_be(h4) .. u32_to_be(h5) .. u32_to_be(h6) .. u32_to_be(h7)
end

-- ------------------------------------------------------------
-- HMAC-SHA256 (pure Lua)
-- ------------------------------------------------------------
local function hmac_sha256(key, message)
  local block = 64
  if #key > block then
    key = sha256(key)
  end
  if #key < block then
    key = key .. string.rep("\0", block - #key)
  end

  local o_key, i_key = {}, {}
  for i = 1, block do
    local kb = key:byte(i)
    o_key[i] = string.char(bxor(kb, 0x5c))
    i_key[i] = string.char(bxor(kb, 0x36))
  end
  o_key = table.concat(o_key)
  i_key = table.concat(i_key)

  return sha256(o_key .. sha256(i_key .. message))
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
