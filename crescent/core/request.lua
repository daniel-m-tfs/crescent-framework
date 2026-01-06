-- crescent/core/request.lua
-- Processamento e validação de requisições HTTP

local json = _G._json or require("json")
local string_utils = require("crescent.utils.string")

local M = {}

-- Tamanho máximo do body (10MB por padrão)
local MAX_BODY_SIZE = 10 * 1024 * 1024

-- Lê o body da requisição de forma assíncrona
function M.read_body(req, max_size, callback)
    max_size = max_size or MAX_BODY_SIZE
    local chunks = {}
    local total_size = 0
    
    req:on("data", function(chunk)
        total_size = total_size + #chunk
        
        -- Proteção contra DoS: limita tamanho do body
        if total_size > max_size then
            req:destroy()
            return callback(nil, nil, "body too large")
        end
        
        chunks[#chunks + 1] = chunk
    end)
    
    req:on("end", function()
        local raw = table.concat(chunks)
        local ct = (req.headers["content-type"] or ""):lower()
        
        -- Parse JSON se aplicável
        if ct:find("application/json", 1, true) and raw ~= "" then
            local ok, data = pcall(json.parse, raw)
            if ok then
                callback(raw, data)
            else
                callback(raw, nil, "invalid json")
            end
        else
            callback(raw, nil)
        end
    end)
    
    req:on("error", function(err)
        callback(nil, nil, "request error: " .. tostring(err))
    end)
end

-- Valida Content-Type
function M.validate_content_type(req, expected)
    local ct = (req.headers["content-type"] or ""):lower()
    if type(expected) == "string" then
        return ct:find(expected, 1, true) ~= nil
    elseif type(expected) == "table" then
        for _, exp in ipairs(expected) do
            if ct:find(exp, 1, true) then
                return true
            end
        end
    end
    return false
end

-- Valida tamanho do body via Content-Length
function M.validate_content_length(req, max_size)
    max_size = max_size or MAX_BODY_SIZE
    local cl = req.headers["content-length"]
    
    if cl then
        local size = tonumber(cl)
        if size and size > max_size then
            return false, "content-length exceeds maximum"
        end
    end
    
    return true
end

-- Configura tamanho máximo do body
function M.set_max_body_size(size)
    MAX_BODY_SIZE = size
end

-- Obtém tamanho máximo do body
function M.get_max_body_size()
    return MAX_BODY_SIZE
end

return M
