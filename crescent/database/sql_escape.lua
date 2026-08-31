-- crescent/database/sql_escape.lua
-- Fonte única de escaping de valores e identificadores SQL,
-- compartilhada por query_builder.lua e mysql.lua

local M = {}

-- Escapa um valor Lua e retorna o literal SQL pronto para uso (já entre aspas quando aplicável)
function M.escape_value(value)
    if type(value) == "string" then
        -- Escape de aspas simples (duplicar) e backslashes
        local escaped = value:gsub("\\", "\\\\"):gsub("'", "''")
        -- Remove caracteres nulos que podem causar problemas
        escaped = escaped:gsub("\0", "")
        return "'" .. escaped .. "'"
    elseif type(value) == "number" then
        -- Valida que é realmente um número
        if value ~= value then -- NaN check
            return "NULL"
        end
        return tostring(value)
    elseif type(value) == "boolean" then
        return value and "1" or "0"
    elseif value == nil then
        return "NULL"
    else
        -- Fallback: converte para string e escapa
        local str = tostring(value):gsub("\\", "\\\\"):gsub("'", "''"):gsub("\0", "")
        return "'" .. str .. "'"
    end
end

-- Escapa um identificador (nome de coluna/tabela) envolvendo em backticks.
-- Suporta identificadores qualificados ("tabela.coluna" -> `tabela`.`coluna`)
function M.escape_identifier(identifier)
    local parts = {}
    for part in identifier:gmatch("[^.]+") do
        table.insert(parts, "`" .. part:gsub("`", "") .. "`")
    end
    if #parts == 0 then
        return "``"
    end
    return table.concat(parts, ".")
end

return M
