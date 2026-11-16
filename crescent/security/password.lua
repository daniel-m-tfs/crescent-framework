-- Password hashing with PBKDF2-HMAC-SHA256 computed natively by OpenSSL.
--
-- Stored format (compatible with the original Crescent `hash.encrypt`):
--   <iterations>$<salt hex, 16 bytes>$<derived key hex, 32 bytes>
--
-- The derivation still runs synchronously inside the nginx worker. Measured
-- under resty (OpenSSL 3.5, Apple M-series): 100k ≈ 11 ms, 210k ≈ 23 ms,
-- 600k ≈ 64 ms per hash/verify. The default follows OWASP's 600k; lower it
-- with PASSWORD_HASH_ITERATIONS on slow hardware and rate-limit login routes.
local kdf = require("resty.openssl.kdf")
local Env = require("crescent.env")
local Crypto = require("crescent.security.crypto")

local Password = {}

Password.DEFAULT_ITERATIONS = 600000
Password.MAX_ITERATIONS = 5000000
local SALT_LENGTH = 16
local KEY_LENGTH = 32

local function default_iterations()
    return Env.number("PASSWORD_HASH_ITERATIONS", Password.DEFAULT_ITERATIONS)
end

local function valid_iterations(value)
    return type(value) == "number" and value % 1 == 0 and value >= 1 and value <= Password.MAX_ITERATIONS
end

local function derive(password, salt, iterations)
    local key, err = kdf.derive({
        type = kdf.PBKDF2,
        md = "sha256",
        pass = password,
        salt = salt,
        pbkdf2_iter = iterations,
        outlen = KEY_LENGTH,
    })
    if not key then error("PBKDF2 failed: " .. tostring(err), 3) end
    return key
end

-- Returns iterations, salt (bytes), key (bytes) or nil for anything malformed.
local function parse(stored)
    if type(stored) ~= "string" then return nil end
    local iterations, salt_hex, key_hex = stored:match("^(%d+)%$(%x+)%$(%x+)$")
    if not iterations then return nil end
    iterations = tonumber(iterations)
    if not valid_iterations(iterations) then return nil end
    if #salt_hex ~= SALT_LENGTH * 2 or #key_hex ~= KEY_LENGTH * 2 then return nil end
    return iterations, Crypto.from_hex(salt_hex), Crypto.from_hex(key_hex)
end

function Password.hash(password, iterations)
    if type(password) ~= "string" or password == "" then
        error("password must be a non-empty string", 2)
    end
    iterations = iterations or default_iterations()
    if not valid_iterations(iterations) then
        error("PBKDF2 iterations must be an integer between 1 and " .. Password.MAX_ITERATIONS, 2)
    end
    local salt = Crypto.random_bytes(SALT_LENGTH)
    return string.format("%d$%s$%s", iterations, Crypto.to_hex(salt), Crypto.to_hex(derive(password, salt, iterations)))
end

-- Never raises for bad input: a corrupt or legacy value in the database
-- simply does not match.
function Password.verify(password, stored)
    if type(password) ~= "string" or password == "" then return false end
    local iterations, salt, key = parse(stored)
    if not iterations then return false end
    local ok, derived = pcall(derive, password, salt, iterations)
    return ok and Crypto.secure_compare(derived, key)
end

-- True when `stored` is malformed or weaker than `iterations` (default: the
-- current default). Call after a successful verify to upgrade old hashes.
function Password.needs_rehash(stored, iterations)
    local current = parse(stored)
    if not current then return true end
    return current < (iterations or default_iterations())
end

Password.secure_compare = Crypto.secure_compare

return Password
