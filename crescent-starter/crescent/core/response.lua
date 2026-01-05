-- crescent/core/response.lua
-- Utilidades para envio de respostas HTTP

local json = _G._json or require("json")
local headers_utils = require("crescent.utils.headers")

local M = {}

-- Envia resposta JSON
function M.json(res, status, obj, extra_headers)
    if res.finished then return end
    
    res:setHeader("Content-Type", "application/json; charset=utf-8")
    
    -- Headers extras (se fornecidos)
    if type(extra_headers) == "table" then
        for k, v in pairs(extra_headers) do
            if headers_utils.is_safe_value(v) then
                res:setHeader(k, v)
            end
        end
    end
    
    res:writeHead(status or 200)
    
    local ok, encoded = pcall(json.stringify, obj)
    if ok then
        res:finish(encoded)
    else
        res:finish('{"error":"json encoding error"}')
    end
end

-- Envia resposta de texto
function M.text(res, status, str, extra_headers)
    if res.finished then return end
    
    res:setHeader("Content-Type", "text/plain; charset=utf-8")
    
    -- Headers extras (se fornecidos)
    if type(extra_headers) == "table" then
        for k, v in pairs(extra_headers) do
            if headers_utils.is_safe_value(v) then
                res:setHeader(k, v)
            end
        end
    end
    
    res:writeHead(status or 200)
    res:finish(str or "")
end

-- Envia resposta HTML
function M.html(res, status, html, extra_headers)
    if res.finished then return end
    
    res:setHeader("Content-Type", "text/html; charset=utf-8")
    
    -- Headers extras (se fornecidos)
    if type(extra_headers) == "table" then
        for k, v in pairs(extra_headers) do
            if headers_utils.is_safe_value(v) then
                res:setHeader(k, v)
            end
        end
    end
    
    res:writeHead(status or 200)
    res:finish(html or "")
end

-- Envia erro padronizado
function M.error(res, status, message, details)
    local error_obj = {
        error = message or "internal error",
        status = status or 500
    }
    
    if details then
        error_obj.details = details
    end
    
    M.json(res, status, error_obj)
end

-- Envia resposta de redirecionamento
function M.redirect(res, location, status)
    if res.finished then return end
    
    res:setHeader("Location", location)
    res:writeHead(status or 302)
    res:finish()
end

-- Envia resposta vazia (204 No Content)
function M.no_content(res)
    if res.finished then return end
    
    res:writeHead(204)
    res:finish()
end

-- Define headers de segurança padrão
function M.set_security_headers(res)
    res:setHeader("X-Content-Type-Options", "nosniff")
    res:setHeader("X-Frame-Options", "DENY")
    res:setHeader("X-XSS-Protection", "1; mode=block")
    res:setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
end

-- Define headers CORS
function M.set_cors_headers(res, options)
    options = options or {}
    
    res:setHeader("Access-Control-Allow-Origin", options.origin or "*")
    res:setHeader("Access-Control-Allow-Methods", 
                  options.methods or "GET,POST,PUT,PATCH,DELETE,OPTIONS")
    res:setHeader("Access-Control-Allow-Headers", 
                  options.headers or "Content-Type, Authorization")
    
    if options.credentials then
        res:setHeader("Access-Control-Allow-Credentials", "true")
    end
    
    if options.max_age then
        res:setHeader("Access-Control-Max-Age", tostring(options.max_age))
    end
end

return M
