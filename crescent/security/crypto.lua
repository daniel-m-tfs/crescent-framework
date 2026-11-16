-- Small primitives shared by the security modules.
local bit = require("bit")
local rand = require("resty.openssl.rand")
local hmac = require("resty.openssl.hmac")
local to_hex = require("resty.string").to_hex

local bor, bxor, byte = bit.bor, bit.bxor, string.byte

local Crypto = {}

-- Runs in time proportional to the longer input regardless of where the
-- first difference is, so comparisons do not leak a matching prefix.
function Crypto.secure_compare(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    local diff = bxor(#a, #b)
    for i = 1, math.max(#a, #b) do
        diff = bor(diff, bxor(byte(a, i) or 0, byte(b, i) or 0))
    end
    return diff == 0
end

function Crypto.random_bytes(length)
    local bytes, err = rand.bytes(length)
    if not bytes then error("unable to generate random bytes: " .. tostring(err), 2) end
    return bytes
end

function Crypto.random_hex(length)
    return to_hex(Crypto.random_bytes(length))
end

Crypto.to_hex = to_hex

function Crypto.from_hex(hex)
    if type(hex) ~= "string" or #hex % 2 ~= 0 or hex:find("[^0-9a-fA-F]") then return nil end
    return (hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))
end

function Crypto.hmac(digest, key, message)
    local mac, err = hmac.new(key, digest)
    if not mac then error(err, 2) end
    local result, final_err = mac:final(message)
    if not result then error(final_err, 2) end
    return result
end

function Crypto.now()
    return ngx and ngx.time and ngx.time() or os.time()
end

return Crypto
