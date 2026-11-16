-- Strict Base64 (RFC 4648 §4) and Base64URL (§5, unpadded) on top of
-- ngx.encode_base64/ngx.decode_base64. ngx.decode_base64 is lenient (it
-- accepts missing or misplaced padding), so input is validated first and
-- anything malformed returns nil instead of being silently "repaired".
local Base64 = {}

local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64

function Base64.encode(raw)
    return encode_base64(raw)
end

function Base64.decode(text)
    if type(text) ~= "string" or #text % 4 ~= 0 then return nil end
    local data = text:match("^([A-Za-z0-9+/]*)=?=?$")
    if not data or #text - #data > 2 then return nil end
    return decode_base64(text)
end

function Base64.url_encode(raw)
    return (encode_base64(raw, true):gsub("[+/]", { ["+"] = "-", ["/"] = "_" }))
end

function Base64.url_decode(text)
    if type(text) ~= "string" or #text % 4 == 1 or not text:match("^[A-Za-z0-9_%-]*$") then
        return nil
    end
    local standard = text:gsub("[-_]", { ["-"] = "+", ["_"] = "/" })
    return decode_base64(standard .. string.rep("=", (4 - #standard % 4) % 4))
end

return Base64
