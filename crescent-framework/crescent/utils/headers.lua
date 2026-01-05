-- crescent/utils/headers.lua
-- Utilidades para normalização e manipulação segura de headers HTTP

local string_utils = require("crescent.utils.string")
local trim = string_utils.trim

local M = {}

-- Define header de forma segura
local function set_header(out, k, v)
    if not k then return end
    k = tostring(k)
    -- Validação básica de segurança (previne header injection)
    if k:find("\r") or k:find("\n") or k:find("\0") then return end
    out[string.lower(k)] = trim(v and tostring(v) or "")
end

-- Normaliza headers de diferentes formatos para um formato consistente
function M.normalize(req)
    local out = {}
    if not req then return out end

    -- 1) Preferir rawHeaders: {"Authorization","Bearer xyz","Host","..."}
    local rh = req.rawHeaders
    if type(rh) == "table" and #rh > 0 and (#rh % 2 == 0) then
        for i = 1, #rh, 2 do
            set_header(out, rh[i], rh[i + 1])
        end
        return out
    end

    local h = req.headers
    if type(h) ~= "table" then
        -- Fallback: tentar API getHeader direta
        local v = type(req.getHeader) == "function" and req:getHeader("Authorization") or nil
        set_header(out, "authorization", v)
        return out
    end

    local n = #h
    if n > 0 then
        if type(h[1]) == "string" then
            -- 2) Array de strings
            if n % 2 == 0 then
                -- Alternando nome/valor
                for i = 1, n, 2 do
                    set_header(out, h[i], h[i + 1])
                end
            else
                -- Só nomes -> tenta getHeader
                for i = 1, n do
                    local name = h[i]
                    local v = type(req.getHeader) == "function" and req:getHeader(name) or nil
                    set_header(out, name, v)
                end
            end
            return out
        elseif type(h[1]) == "table" then
            -- 3) Array de pares/tabelas
            for i = 1, n do
                local e = h[i]
                if type(e) == "table" then
                    local k = e[1] or e.name or e.key or e.header or e.k
                    local v = e[2] or e.value or e.v
                    if not v and k and type(req.getHeader) == "function" then
                        v = req:getHeader(k)
                    end
                    set_header(out, k, v)
                end
            end
            return out
        end
    end

    -- 4) Mapa padrão: { ["authorization"]="Bearer xyz" }
    for k, v in pairs(h) do
        if type(v) == "table" then
            v = v[1]
        end
        set_header(out, k, v)
    end

    -- 5) Garantir authorization, se possível
    if not out["authorization"] and type(req.getHeader) == "function" then
        local v = req:getHeader("Authorization")
        if v then
            set_header(out, "authorization", v)
        end
    end

    return out
end

-- Extrai Bearer token do header Authorization
function M.get_bearer(headers)
    if type(headers) ~= "table" then return nil end
    
    local auth = headers["authorization"]
    if not auth or auth == "" then return nil end
    
    local scheme, token = auth:match("^(%S+)%s+(.+)$")
    if not scheme or scheme:lower() ~= "bearer" then
        return nil
    end
    
    return trim(token)
end

-- Valida se o header é seguro (previne header injection)
function M.is_safe_value(value)
    if type(value) ~= "string" then return false end
    -- Rejeita CRLF e null bytes
    return not value:find("[\r\n\0]")
end

return M
