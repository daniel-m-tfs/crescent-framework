-- HTTP cookies (RFC 6265): parsing the Cookie header, serializing
-- Set-Cookie and HMAC-signed values.
--
--   Cookie.parse(header)                      -> { name = value }
--   Cookie.serialize(name, value, options)    -> "name=value; Path=/; ..."
--   Cookie.sign(name, value, secret)          -> "value.signature"
--   Cookie.unsign(name, signed, secrets)      -> value | nil
--   Cookie.secrets(config)                    -> { secret, fallback... }
--
-- Values are percent-encoded on write and decoded on read, so any string
-- round-trips. Signatures bind the cookie name, so a signed value cannot be
-- moved to another cookie.
local Env = require("crescent.env")
local Base64 = require("crescent.security.base64")
local Crypto = require("crescent.security.crypto")

local Cookie = {}

Cookie.MIN_SECRET_LENGTH = 32

local NAME_PATTERN = "^[%w!#$%%&'*+%-.^_`|~]+$"
local SAME_SITE = { strict = "Strict", lax = "Lax", none = "None" }

local function trim(value)
    return (value:match("^%s*(.-)%s*$"))
end

local function decode(value)
    if not value:find("%", 1, true) then return value end
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

-- Everything outside RFC 6265 cookie-octets (plus "%" itself) is encoded.
local function encode(value)
    return (value:gsub("[^%w!#$&'()*+%-./:<=>?@%[%]^_`{|}~]", function(char)
        return string.format("%%%02X", char:byte())
    end))
end

Cookie.encode = encode
Cookie.decode = decode

function Cookie.valid_name(name)
    return type(name) == "string" and name:match(NAME_PATTERN) ~= nil
end

-- Malformed pairs are skipped instead of failing the whole header; when a
-- name repeats, the first (most specific path) wins, as browsers send it.
function Cookie.parse(header)
    local cookies = {}
    if type(header) == "table" then header = table.concat(header, "; ") end
    if type(header) ~= "string" or header == "" then return cookies end
    for pair in header:gmatch("[^;]+") do
        local name, value = pair:match("^%s*([^=]-)%s*=(.*)$")
        if name and Cookie.valid_name(name) and cookies[name] == nil then
            value = trim(value)
            local quoted = value:match('^"(.*)"$')
            if quoted then value = quoted end
            cookies[name] = decode(value)
        end
    end
    return cookies
end

local function attribute(value, label)
    if type(value) ~= "string" or value == "" or value:find("[%z\1-\31\127;]") then
        error("invalid cookie " .. label .. ": " .. tostring(value), 3)
    end
    return value
end

local function http_date(time)
    if ngx and ngx.cookie_time then return ngx.cookie_time(time) end
    return os.date("!%a, %d-%b-%Y %H:%M:%S GMT", time)
end

function Cookie.serialize(name, value, options)
    options = options or {}
    if not Cookie.valid_name(name) then error("invalid cookie name: " .. tostring(name), 2) end
    if type(value) == "number" then value = tostring(value) end
    if type(value) ~= "string" then error("cookie value must be a string", 2) end

    local parts = { name .. "=" .. encode(value) }
    if options.path ~= false then parts[#parts + 1] = "Path=" .. attribute(options.path or "/", "path") end
    if options.domain then parts[#parts + 1] = "Domain=" .. attribute(options.domain, "domain") end
    if options.max_age ~= nil then
        local max_age = options.max_age
        if type(max_age) ~= "number" or max_age ~= max_age then error("cookie max_age must be a number", 2) end
        parts[#parts + 1] = "Max-Age=" .. string.format("%d", math.floor(max_age))
    end
    if options.expires ~= nil then
        local expires = options.expires
        if type(expires) == "number" then expires = http_date(math.floor(expires)) end
        parts[#parts + 1] = "Expires=" .. attribute(expires, "expires")
    end
    if options.http_only ~= false then parts[#parts + 1] = "HttpOnly" end
    if options.secure then parts[#parts + 1] = "Secure" end
    if options.same_site ~= false then
        local same_site = SAME_SITE[tostring(options.same_site or "Lax"):lower()]
        if not same_site then error("cookie same_site must be Strict, Lax or None", 2) end
        if same_site == "None" and not options.secure then
            error("cookie same_site=None requires secure = true", 2)
        end
        parts[#parts + 1] = "SameSite=" .. same_site
    end
    if options.partitioned then parts[#parts + 1] = "Partitioned" end
    return table.concat(parts, "; ")
end

local function signature(name, value, secret)
    return Base64.url_encode(Crypto.hmac("sha256", secret, "crescent.cookie\0" .. name .. "\0" .. value))
end

function Cookie.sign(name, value, secret)
    return value .. "." .. signature(name, value, secret)
end

-- Tries every secret (current first, then fallbacks) so keys can be rotated
-- without logging everybody out.
function Cookie.unsign(name, signed, secrets)
    if type(signed) ~= "string" then return nil end
    local value, mac = signed:match("^(.*)%.([A-Za-z0-9_%-]+)$")
    if not value then return nil end
    for _, secret in ipairs(secrets) do
        if Crypto.secure_compare(mac, signature(name, value, secret)) then return value end
    end
    return nil
end

local function check_secret(secret, label)
    if type(secret) ~= "string" or #secret < Cookie.MIN_SECRET_LENGTH then
        error(label .. " must be a string of at least " .. Cookie.MIN_SECRET_LENGTH .. " characters", 3)
    end
    return secret
end

-- Signing secrets from `secret` (or config.secret_key, then the APP_KEY
-- environment variable) followed by `fallbacks`/config.secret_key_fallbacks.
function Cookie.secrets(config, secret, fallbacks)
    config = config or {}
    secret = secret or config.secret_key or Env.get("APP_KEY")
    if secret == nil then
        error("no secret configured: set config.secret_key or the APP_KEY environment variable", 2)
    end
    local list = { check_secret(secret, "secret_key") }
    fallbacks = fallbacks or config.secret_key_fallbacks
    if type(fallbacks) == "string" then fallbacks = { fallbacks } end
    for _, old in ipairs(fallbacks or {}) do
        list[#list + 1] = check_secret(old, "secret_key_fallbacks entries")
    end
    return list
end

return Cookie
