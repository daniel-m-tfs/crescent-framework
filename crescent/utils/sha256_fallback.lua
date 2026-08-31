-- crescent/utils/sha256_fallback.lua
-- SHA-256 / HMAC-SHA256 pure-Lua, usado apenas quando o driver openssl não
-- está disponível (crescent/utils/jwt.lua tenta openssl primeiro)

local M = {}

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

function M.sha256(raw)
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

function M.hmac_sha256(key, message)
  local block = 64
  if #key > block then
    key = M.sha256(key)
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

  return M.sha256(o_key .. M.sha256(i_key .. message))
end

return M
