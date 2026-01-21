-- HTTP Client Library for Crescent Framework
-- Provides an easy-to-use interface for consuming external APIs
-- Similar to axios in Node.js

local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("cjson")

local HttpClient = {}
HttpClient.__index = HttpClient

-- Create a new HTTP client instance
function HttpClient.new(config)
    local self = setmetatable({}, HttpClient)
    self.baseURL = config and config.baseURL or ""
    self.timeout = config and config.timeout or 30
    self.headers = config and config.headers or {}
    return self
end

-- Parse URL to determine if it's HTTPS
local function is_https(url)
    return url:match("^https://") ~= nil
end

-- Merge two tables
local function merge_tables(t1, t2)
    local result = {}
    for k, v in pairs(t1 or {}) do
        result[k] = v
    end
    for k, v in pairs(t2 or {}) do
        result[k] = v
    end
    return result
end

-- Build query string from table
local function build_query_string(params)
    if not params then return "" end
    
    local parts = {}
    for key, value in pairs(params) do
        table.insert(parts, key .. "=" .. tostring(value))
    end
    
    if #parts == 0 then return "" end
    return "?" .. table.concat(parts, "&")
end

-- Perform HTTP request
function HttpClient:request(config)
    local url = config.url or ""
    
    -- Add baseURL if present
    if self.baseURL ~= "" and not url:match("^https?://") then
        url = self.baseURL .. url
    end
    
    -- Add query params
    if config.params then
        url = url .. build_query_string(config.params)
    end
    
    -- Prepare headers
    local headers = merge_tables(self.headers, config.headers)
    
    -- Prepare request body
    local request_body = ""
    if config.data then
        if type(config.data) == "table" then
            request_body = json.encode(config.data)
            headers["content-type"] = headers["content-type"] or "application/json"
        else
            request_body = tostring(config.data)
        end
        headers["content-length"] = #request_body
    end
    
    -- Response storage
    local response_body = {}
    
    -- Prepare request options
    local request_options = {
        url = url,
        method = config.method or "GET",
        headers = headers,
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body),
        redirect = config.redirect ~= false
    }
    
    -- Choose HTTP or HTTPS
    local request_func = is_https(url) and https.request or http.request
    
    -- Perform request
    local response, status_code, response_headers, status_line = request_func(request_options)
    
    -- Parse response body
    local body = table.concat(response_body)
    local data = body
    
    -- Try to parse JSON
    local success, parsed = pcall(function()
        return json.decode(body)
    end)
    
    if success then
        data = parsed
    end
    
    -- Build response object
    local result = {
        data = data,
        status = status_code or (response == 1 and 200 or 500),
        statusText = status_line or "",
        headers = response_headers or {},
        config = config,
        request = request_options
    }
    
    -- Check for errors
    if not response or (status_code and (status_code < 200 or status_code >= 400)) then
        result.error = true
        result.message = "Request failed with status " .. (status_code or "unknown")
        return nil, result
    end
    
    return result, nil
end

-- Convenience methods
function HttpClient:get(url, config)
    config = config or {}
    config.url = url
    config.method = "GET"
    return self:request(config)
end

function HttpClient:post(url, data, config)
    config = config or {}
    config.url = url
    config.method = "POST"
    config.data = data
    return self:request(config)
end

function HttpClient:put(url, data, config)
    config = config or {}
    config.url = url
    config.method = "PUT"
    config.data = data
    return self:request(config)
end

function HttpClient:patch(url, data, config)
    config = config or {}
    config.url = url
    config.method = "PATCH"
    config.data = data
    return self:request(config)
end

function HttpClient:delete(url, config)
    config = config or {}
    config.url = url
    config.method = "DELETE"
    return self:request(config)
end

function HttpClient:head(url, config)
    config = config or {}
    config.url = url
    config.method = "HEAD"
    return self:request(config)
end

function HttpClient:options(url, config)
    config = config or {}
    config.url = url
    config.method = "OPTIONS"
    return self:request(config)
end

-- Create default instance
local default_instance = HttpClient.new()

-- Export module with default instance methods
local exports = {
    create = function(config)
        return HttpClient.new(config)
    end,
    
    request = function(config)
        return default_instance:request(config)
    end,
    
    get = function(url, config)
        return default_instance:get(url, config)
    end,
    
    post = function(url, data, config)
        return default_instance:post(url, data, config)
    end,
    
    put = function(url, data, config)
        return default_instance:put(url, data, config)
    end,
    
    patch = function(url, data, config)
        return default_instance:patch(url, data, config)
    end,
    
    delete = function(url, config)
        return default_instance:delete(url, config)
    end,
    
    head = function(url, config)
        return default_instance:head(url, config)
    end,
    
    options = function(url, config)
        return default_instance:options(url, config)
    end
}

return exports
