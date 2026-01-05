-- crescent/utils/string.lua
-- Utilidades para manipulação de strings com foco em segurança

local M = {}

-- Escapa padrões Lua para evitar injeção de padrões
function M.escape_lua_pattern(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("%%", "%%%%")
             :gsub("%^", "%%^")
             :gsub("%$", "%%$")
             :gsub("%(", "%%(")
             :gsub("%)", "%%)")
             :gsub("%.", "%%.")
             :gsub("%[", "%%[")
             :gsub("%]", "%%]")
             :gsub("%*", "%%*")
             :gsub("%+", "%%+")
             :gsub("%-", "%%-")
             :gsub("%?", "%%?"))
end

-- Remove espaços em branco do início e fim
function M.trim(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$")
end

-- Valida se a string é segura (sem caracteres de controle perigosos)
function M.is_safe(s)
    if type(s) ~= "string" then return false end
    -- Rejeita caracteres de controle exceto \t, \r, \n
    return not s:find("[\0-\8\11-\12\14-\31\127]")
end

-- Sanitiza string removendo caracteres perigosos
function M.sanitize(s)
    if type(s) ~= "string" then return "" end
    return s:gsub("[\0-\8\11-\12\14-\31\127]", "")
end

-- Limita o tamanho da string (proteção contra DoS)
function M.limit(s, max_len)
    if type(s) ~= "string" then return "" end
    max_len = max_len or 8192
    if #s > max_len then
        return s:sub(1, max_len)
    end
    return s
end

return M
