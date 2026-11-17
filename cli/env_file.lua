-- Reads and edits the project's .env without touching unrelated lines.
local fs = require("cli.fs")

local EnvFile = {}

-- 48 random bytes as hex, from /dev/urandom (works on plain Lua and resty).
function EnvFile.random_secret(bytes)
    bytes = bytes or 48
    local file = io.open("/dev/urandom", "rb")
    if not file then return nil end
    local raw = file:read(bytes)
    file:close()
    if not raw or #raw ~= bytes then return nil end
    return (raw:gsub(".", function(char) return string.format("%02x", char:byte()) end))
end

-- Value of KEY in the .env text (unquoted), or nil.
function EnvFile.get(text, key)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local value = line:match("^%s*" .. key .. "%s*=%s*(.-)%s*$")
        if value then return (value:match('^"(.*)"$') or value:match("^'(.*)'$") or value) end
    end
    return nil
end

-- Replaces KEY=... lines (or appends them) for every key in `values`.
function EnvFile.set(text, values)
    local seen = {}
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local key = line:match("^%s*([%a_][%w_]*)%s*=")
        if key and values[key] ~= nil then
            line = key .. "=" .. values[key]
            seen[key] = true
        end
        lines[#lines + 1] = line
    end
    if lines[#lines] == "" then lines[#lines] = nil end
    local missing = {}
    for key in pairs(values) do
        if not seen[key] then missing[#missing + 1] = key end
    end
    table.sort(missing)
    for _, key in ipairs(missing) do lines[#lines + 1] = key .. "=" .. values[key] end
    return table.concat(lines, "\n") .. "\n"
end

-- Fills empty APP_KEY/JWT_SECRET with fresh secrets.
function EnvFile.with_secrets(text)
    local values = {}
    for _, key in ipairs({ "APP_KEY", "JWT_SECRET" }) do
        local current = EnvFile.get(text, key)
        if current == nil or current == "" then
            local secret = EnvFile.random_secret()
            if not secret then return nil, "unable to read /dev/urandom" end
            values[key] = secret
        end
    end
    if next(values) == nil then return text end
    return EnvFile.set(text, values)
end

-- Creates <root>/.env from .env.example with fresh secrets. Returns
-- true (created), false (already existed) or nil, err.
function EnvFile.ensure(root)
    local path = fs.join(root, ".env")
    if fs.exists(path) then return false end
    local example = fs.read(fs.join(root, ".env.example"))
    if not example then return nil, ".env.example not found" end
    local content, err = EnvFile.with_secrets(example)
    if not content then return nil, err end
    local ok, write_error = fs.write_new(path, content)
    if not ok then return nil, write_error end
    return true
end

function EnvFile.write(root, content)
    local file, err = io.open(fs.join(root, ".env"), "wb")
    if not file then return nil, err end
    file:write(content)
    file:close()
    return true
end

return EnvFile
