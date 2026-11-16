-- Thin wrapper around cjson.safe with the framework's encoding policy.
-- Decoded arrays keep an array metatable, so `[]` round-trips as `[]`
-- instead of turning into `{}`. Use `json.empty_array` to send an empty list.
local ok, cjson = pcall(require, "cjson.safe")
if not ok then cjson = nil end

local json = {}

if cjson then
    cjson = cjson.new()
    cjson.decode_array_with_array_mt(true)
    cjson.encode_escape_forward_slash(false)
    json.empty_array = cjson.empty_array
    json.array_mt = cjson.array_mt
else
    json.empty_array = setmetatable({}, { __name = "empty_array" })
    json.array_mt = {}
end

function json.available()
    return cjson ~= nil
end

function json.encode(value)
    if not cjson then return nil, "cjson is required for JSON support" end
    return cjson.encode(value)
end

function json.decode(text)
    if not cjson then return nil, "cjson is required for JSON support" end
    return cjson.decode(text)
end

-- Marks a Lua sequence so it always encodes as a JSON array, even when empty.
function json.array(items)
    return setmetatable(items or {}, json.array_mt)
end

return json
