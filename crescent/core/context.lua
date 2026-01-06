-- crescent/core/context.lua
-- Context object que encapsula request e response

local url = _G._url or require("url")
local qs = _G._querystring or require("querystring")
local headers_utils = require("crescent.utils.headers")
local response = require("crescent.core.response")

local M = {}

-- Cria novo context para uma requisição
function M.new(req, res, router_match)
    local parsed = url.parse(req.url or "/")
    local path = parsed.pathname or "/"
    local query = qs.parse(parsed.query or "")
    
    local handler = router_match and router_match.handler
    local params = router_match and router_match.params or {}
    local route_path = router_match and router_match.route_path
    
    -- Normaliza headers
    local headers = headers_utils.normalize(req)
    
    local ctx = {
        req = req,
        res = res,
        method = req.method,
        path = path,
        route = route_path,
        params = params,
        query = query,
        headers = headers,
        raw = nil,
        body = nil,
        jsonErr = nil,
        state = {} -- Estado customizado para middlewares
    }
    
    -- Métodos de resposta convenientes
    ctx.json = function(status, obj, extra_headers)
        return response.json(res, status, obj, extra_headers)
    end
    
    ctx.text = function(status, str, extra_headers)
        return response.text(res, status, str, extra_headers)
    end
    
    ctx.html = function(status, html, extra_headers)
        return response.html(res, status, html, extra_headers)
    end
    
    ctx.error = function(status, message, details)
        return response.error(res, status, message, details)
    end
    
    ctx.redirect = function(location, status)
        return response.redirect(res, location, status)
    end
    
    ctx.no_content = function()
        return response.no_content(res)
    end
    
    -- Helper para obter header
    ctx.getHeader = function(name)
        return (name and headers[string.lower(name)]) or nil
    end
    
    -- Helper para obter Bearer token
    ctx.getBearer = function()
        return headers_utils.get_bearer(headers)
    end
    
    -- Completa params ausentes com query (ex.: /user?id=1)
    for k, v in pairs(query) do
        if ctx.params[k] == nil then
            ctx.params[k] = v
        end
    end
    
    return ctx
end

-- Define body no context (chamado após leitura)
function M.set_body(ctx, raw, parsed, error)
    ctx.raw = raw
    ctx.body = parsed
    ctx.jsonErr = error
end

return M
