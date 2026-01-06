-- crescent/utils/path.lua
-- Utilidades para manipulação de paths HTTP

local string_utils = require("crescent.utils.string")
local escape_lua_pattern = string_utils.escape_lua_pattern

local M = {}

-- Junta dois paths de forma segura
function M.join(a, b)
    a = a or ""
    b = b or ""
    
    -- Normaliza a
    if a ~= "" and a:sub(-1) == "/" then
        a = a:sub(1, -2)
    end
    
    -- Normaliza b
    if b ~= "" and b:sub(1, 1) ~= "/" then
        b = "/" .. b
    end
    
    -- Retorna resultado
    if a == "" then
        return (b == "" and "/" or b)
    end
    return a .. (b == "" and "" or b)
end

-- Compila path template "/user/{id}" em pattern Lua e lista de parâmetros
-- Retorna: pattern, names
function M.compile(template)
    if type(template) ~= "string" or template == "" then
        return "^/$", {}
    end
    
    if template == "/" then
        return "^/$", {}
    end

    local names, parts, segments = {}, {}, {}

    -- Coleta segmentos sem a barra inicial
    for seg in template:gsub("^/", ""):gmatch("[^/]+") do
        table.insert(segments, seg)
    end

    for i, seg in ipairs(segments) do
        local name = seg:match("^%{%s*([_%w]+)%s*%}$") -- "{id}"
        local is_last = (i == #segments)

        if name then
            table.insert(names, name)
            if is_last then
                -- Último param é opcional: aceita "/user" e "/user/123"
                table.insert(parts, "/?([^/]*)")
            else
                -- Params no meio são obrigatórios
                table.insert(parts, "/([^/]+)")
            end
        else
            -- Literal (escapa metacaracteres de pattern)
            table.insert(parts, "/" .. escape_lua_pattern(seg))
        end
    end

    local pat = "^" .. (#parts > 0 and table.concat(parts) or "/") .. "$"
    return pat, names
end

-- Valida se o path é seguro (sem path traversal)
function M.is_safe(path)
    if type(path) ~= "string" then return false end
    -- Rejeita tentativas de path traversal
    if path:find("%.%.", 1, true) then return false end
    -- Rejeita null bytes
    if path:find("\0") then return false end
    return true
end

-- Normaliza path removendo duplicações de /
function M.normalize(path)
    if type(path) ~= "string" then return "/" end
    -- Remove duplicações de /
    path = path:gsub("/+", "/")
    -- Garante que começa com /
    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    return path
end

return M
