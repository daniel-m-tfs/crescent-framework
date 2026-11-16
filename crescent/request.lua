-- Builds the framework request table from the OpenResty `ngx` API.
-- Everything ngx-specific about reading a request lives here, so the rest of
-- the framework can be exercised with plain tables.
local json = require("crescent.json")
local Upload = require("crescent.upload")

local Request = {}

local MAX_HEADERS = 100
local MAX_ARGS = 100

local function decode_form_component(value)
    value = value:gsub("+", " ")
    if value:find("%%[^0-9a-fA-F]") or value:find("%%[0-9a-fA-F]?$") then return nil end
    return (value:gsub("%%([0-9a-fA-F][0-9a-fA-F])", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

function Request.parse_form(body)
    local result = {}
    for pair in body:gmatch("[^&]+") do
        local key, value = pair:match("^([^=]*)=(.*)$")
        if key == nil then key, value = pair, "" end
        key, value = decode_form_component(key), decode_form_component(value)
        if not key or not value or key == "" then return nil, "malformed form body" end
        if result[key] == nil then
            result[key] = value
        elseif type(result[key]) == "table" then
            result[key][#result[key] + 1] = value
        else
            result[key] = { result[key], value }
        end
    end
    return result
end

-- Bodies larger than `client_body_buffer_size` are spooled to a temporary
-- file by nginx, and `get_body_data()` returns nil for them.
local function read_body(ngx_api)
    ngx_api.req.read_body()
    local body = ngx_api.req.get_body_data()
    if body then return body end
    local path = ngx_api.req.get_body_file and ngx_api.req.get_body_file()
    if not path then return nil end
    local file, open_error = io.open(path, "rb")
    if not file then return nil, open_error end
    body = file:read("*a")
    file:close()
    return body
end

function Request.decode_body(request, body)
    request.raw_body = body
    if not body or body == "" then return request end
    local content_type = request.headers["content-type"]
    if type(content_type) == "table" then content_type = content_type[1] end
    content_type = (content_type or ""):lower()
    if content_type:match("^application/json") or content_type:match("^application/[%w.%-]+%+json") then
        local decoded, decode_error = json.decode(body)
        if decoded == nil then
            request.body_error = decode_error or "malformed JSON body"
            request.body_error_code = json.available() and "malformed_json" or "json_unavailable"
        else
            request.body = decoded
        end
    elseif content_type:match("^application/x%-www%-form%-urlencoded") then
        local decoded, decode_error = Request.parse_form(body)
        if not decoded then
            request.body_error = decode_error
            request.body_error_code = "malformed_form"
        else
            request.body = decoded
        end
    else
        request.body = body
    end
    return request
end

-- `config` (the application config) carries the upload settings.
function Request.from_ngx(ngx_api, config)
    local headers = {}
    local raw_headers = ngx_api.req.get_headers(MAX_HEADERS)
    for key, value in pairs(raw_headers) do headers[string.lower(key)] = value end
    local request = {
        method = ngx_api.req.get_method(),
        path = ngx_api.var.uri or "/",
        headers = headers,
        query = ngx_api.req.get_uri_args(MAX_ARGS),
        remote_addr = ngx_api.var.remote_addr,
        upstream_request_id = headers["x-request-id"],
        request_id = ngx_api.var.request_id,
    }
    -- resty.upload streams the body from the socket itself, so read_body /
    -- get_body_data must not run first.
    local content_type = headers["content-type"]
    if type(content_type) == "table" then content_type = content_type[1] end
    if Upload.is_multipart(content_type) then
        return Upload.read_request(ngx_api, request, config)
    end
    local body, read_error = read_body(ngx_api)
    if read_error then
        request.body_error = "unable to read request body"
        request.body_error_code = "body_unreadable"
        return request
    end
    return Request.decode_body(request, body)
end

-- Deletes temporary upload files the action did not keep.
function Request.cleanup(request)
    if request and request.files then Upload.cleanup(request.files) end
end

return Request
