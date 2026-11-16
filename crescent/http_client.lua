-- Axios-like HTTP client on lua-resty-http (non-blocking cosockets). Usable
-- wherever cosockets are allowed: content/access/rewrite phases, ngx.timer
-- and `resty` scripts; not in init_by_lua, set_by_lua, header/body filters
-- or log phases.
--
--   local HttpClient = require("crescent.http_client")
--   local api = HttpClient.new({ base_url = "https://api.example.com", timeout = 5 })
--   local res, err = api:get("/users", { params = { page = 2 } })
--   -- res = { status, headers, body, data }; err = { message, status?, ... }
--
-- Responses with status >= 400 return `nil, err` where err also carries
-- status/headers/body/data. Redirects are not followed.
local json = require("crescent.json")

local HttpClient = {}
HttpClient.__index = HttpClient

local DEFAULT_MAX_RESPONSE_SIZE = 10 * 1024 * 1024
local CHUNK_SIZE = 16 * 1024
local VALID_METHODS = {
    GET = true, POST = true, PUT = true, PATCH = true,
    DELETE = true, HEAD = true, OPTIONS = true,
}

local error_mt = { __tostring = function(err) return err.message end }

local function failure(message, extra)
    local err = extra or {}
    err.error = true
    err.message = message
    return nil, setmetatable(err, error_mt)
end

local function default_factory()
    return require("resty.http").new()
end

local function url_encode(value)
    return (tostring(value):gsub("[^%w%-_%.~]", function(char)
        return string.format("%%%02X", char:byte())
    end))
end

-- Sorted keys keep the query string deterministic; list values repeat the key.
local function encode_query(params)
    local entries = {}
    for key, value in pairs(params) do entries[#entries + 1] = { tostring(key), value } end
    table.sort(entries, function(left, right) return left[1] < right[1] end)
    local parts = {}
    for _, entry in ipairs(entries) do
        local key, value = entry[1], entry[2]
        if type(value) == "table" then
            for _, item in ipairs(value) do parts[#parts + 1] = url_encode(key) .. "=" .. url_encode(item) end
        elseif value == true then
            parts[#parts + 1] = url_encode(key)
        elseif value ~= false then
            parts[#parts + 1] = url_encode(key) .. "=" .. url_encode(value)
        end
    end
    return table.concat(parts, "&")
end

function HttpClient.parse_url(url)
    if type(url) ~= "string" or url:find("[%s%z]") then return nil, "invalid URL" end
    local scheme, rest = url:match("^(%a[%w+.-]*)://(.+)$")
    if not scheme then return nil, "invalid URL: " .. url end
    scheme = scheme:lower()
    if scheme ~= "http" and scheme ~= "https" then return nil, "unsupported URL scheme: " .. scheme end
    rest = rest:gsub("#.*$", "")
    local authority, path = rest:match("^([^/%?]*)(.*)$")
    if authority:find("@", 1, true) then return nil, "credentials in URL are not supported" end
    local host, port = authority:match("^(%[[%x:.]+%])(.*)$")
    if not host then host, port = authority:match("^([%w%.%-]+)(.*)$") end
    if not host or host == "" then return nil, "invalid URL host: " .. url end
    if port ~= "" then
        port = port:match("^:(%d+)$")
        port = tonumber(port)
        if not port or port < 1 or port > 65535 then return nil, "invalid URL port: " .. url end
    else
        port = scheme == "https" and 443 or 80
    end
    if path == "" then path = "/" elseif path:sub(1, 1) == "?" then path = "/" .. path end
    local query = path:match("%?(.*)$")
    path = path:gsub("%?.*$", "")
    return { scheme = scheme, host = host:gsub("^%[(.*)%]$", "%1"), port = port, path = path, query = query }
end

-- config: base_url (or baseURL), timeout (seconds, default 30), headers,
-- max_response_size (bytes, default 10 MiB), ssl_verify (default true),
-- keepalive_timeout (ms, default 60000), keepalive_pool (default 30),
-- factory (returns a resty.http-compatible object; for tests).
function HttpClient.new(config)
    config = config or {}
    return setmetatable({
        base_url = config.base_url or config.baseURL or "",
        timeout = config.timeout or 30,
        headers = config.headers or {},
        max_response_size = config.max_response_size or DEFAULT_MAX_RESPONSE_SIZE,
        ssl_verify = config.ssl_verify ~= false,
        keepalive_timeout = config.keepalive_timeout or 60000,
        keepalive_pool = config.keepalive_pool or 30,
        factory = config.factory or default_factory,
    }, HttpClient)
end

local function build_headers(defaults, overrides)
    local headers, names = {}, {}
    for _, source in ipairs({ defaults or {}, overrides or {} }) do
        for name, value in pairs(source) do
            if type(name) ~= "string" or not name:match("^[%w!#$%%&'*+%-.^_`|~]+$") then
                return nil, "invalid header name: " .. tostring(name)
            end
            value = tostring(value)
            if value:find("[%z\r\n]") then return nil, "invalid value for header " .. name end
            local lower = name:lower()
            if names[lower] then headers[names[lower]] = nil end
            names[lower] = name
            headers[name] = value
        end
    end
    return headers, names
end

local function looks_like_json(content_type, body)
    if type(content_type) == "table" then content_type = content_type[1] end
    if type(content_type) == "string" and content_type:lower():find("json", 1, true) then return true end
    return body:match("^%s*[%[{]") ~= nil
end

local function header(headers, name)
    if type(headers) ~= "table" then return nil end
    local value = headers[name]
    if value ~= nil then return value end
    local lower = name:lower()
    for key, candidate in pairs(headers) do
        if type(key) == "string" and key:lower() == lower then return candidate end
    end
    return nil
end

local function read_body(res, limit)
    local length = tonumber(header(res.headers, "Content-Length"))
    if length and length > limit then return nil, "response too large" end
    local reader = res.body_reader
    if not reader then
        if res.read_body then
            local body, err = res:read_body()
            if not body then return nil, err end
            if #body > limit then return nil, "response too large" end
            return body
        end
        return ""
    end
    local chunks, size = {}, 0
    repeat
        local chunk, err = reader(CHUNK_SIZE)
        if err then return nil, err end
        if chunk then
            size = size + #chunk
            if size > limit then return nil, "response too large" end
            chunks[#chunks + 1] = chunk
        end
    until not chunk
    return table.concat(chunks)
end

function HttpClient:request(config)
    config = config or {}
    local method = string.upper(config.method or "GET")
    if not VALID_METHODS[method] then return failure("invalid HTTP method: " .. tostring(config.method)) end

    local url = config.url or ""
    if url == "" then
        url = self.base_url
    elseif not url:match("^%a[%w+.-]*://") then
        url = self.base_url:gsub("/$", "") .. "/" .. url:gsub("^/", "")
    end
    local target, parse_error = HttpClient.parse_url(url)
    if not target then return failure(parse_error) end

    local limit = config.max_response_size or self.max_response_size
    if type(limit) ~= "number" or limit <= 0 then return failure("invalid max_response_size") end

    local headers, names = build_headers(self.headers, config.headers)
    if not headers then return failure(names) end

    local body
    if config.data ~= nil then
        if type(config.data) == "table" then
            local encoded, encode_error = json.encode(config.data)
            if not encoded then return failure("unable to encode request body: " .. tostring(encode_error)) end
            body = encoded
            if not names["content-type"] then headers["Content-Type"] = "application/json" end
        else
            body = tostring(config.data)
        end
    end
    if not names["accept"] then headers["Accept"] = "application/json, text/plain, */*" end

    local query = target.query
    if config.params and next(config.params) then
        local encoded = encode_query(config.params)
        query = (query and query ~= "") and (query .. "&" .. encoded) or encoded
    end
    local path = target.path
    if query and query ~= "" then path = path .. "?" .. query end

    local httpc, factory_error = self.factory()
    if not httpc then return failure("unable to create HTTP client: " .. tostring(factory_error)) end
    local timeout_ms = math.floor((config.timeout or self.timeout) * 1000)
    httpc:set_timeouts(timeout_ms, timeout_ms, timeout_ms)

    local connected, connect_error = httpc:connect({
        scheme = target.scheme,
        host = target.host,
        port = target.port,
        ssl_verify = self.ssl_verify,
        ssl_server_name = target.host,
        pool_size = self.keepalive_pool,
    })
    if not connected then
        return failure("connection failed: " .. tostring(connect_error), { config = config })
    end

    local res, request_error = httpc:request({ method = method, path = path, headers = headers, body = body })
    if not res then
        httpc:close()
        return failure("request failed: " .. tostring(request_error), { config = config })
    end

    local response_body, read_error = read_body(res, limit)
    if not response_body then
        httpc:close()
        return failure(read_error == "response too large" and read_error
            or ("failed to read response: " .. tostring(read_error)), { status = res.status, config = config })
    end
    if not httpc:set_keepalive(self.keepalive_timeout, self.keepalive_pool) then httpc:close() end

    local data = response_body
    if response_body ~= "" and looks_like_json(header(res.headers, "Content-Type"), response_body) then
        local decoded = json.decode(response_body)
        if decoded ~= nil then data = decoded end
    end

    local result = { status = res.status, headers = res.headers or {}, body = response_body, data = data }
    if res.status >= 400 then
        result.config = config
        return failure("request failed with status " .. res.status, result)
    end
    return result
end

local function shortcut(method, with_body)
    if with_body then
        return function(self, url, data, config)
            config = config or {}
            config.url, config.method, config.data = url, method, data
            return self:request(config)
        end
    end
    return function(self, url, config)
        config = config or {}
        config.url, config.method = url, method
        return self:request(config)
    end
end

HttpClient.get = shortcut("GET")
HttpClient.delete = shortcut("DELETE")
HttpClient.head = shortcut("HEAD")
HttpClient.options = shortcut("OPTIONS")
HttpClient.post = shortcut("POST", true)
HttpClient.put = shortcut("PUT", true)
HttpClient.patch = shortcut("PATCH", true)

-- Module-level API: HttpClient.new/create plus shortcuts on a default
-- instance (`require("crescent.http_client").get(url)`).
local M = { new = HttpClient.new, create = HttpClient.new, parse_url = HttpClient.parse_url, Client = HttpClient }
local default_instance

local function default()
    default_instance = default_instance or HttpClient.new()
    return default_instance
end

function M.request(config) return default():request(config) end
for _, name in ipairs({ "get", "delete", "head", "options", "post", "put", "patch" }) do
    M[name] = function(...) return HttpClient[name](default(), ...) end
end

return M
