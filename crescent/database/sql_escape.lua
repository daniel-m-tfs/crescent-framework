-- crescent/database/sql_escape.lua
-- Fonte única de escaping de valores e identificadores SQL,
-- compartilhada por query_builder.lua e mysql.lua

local M = {}

-- Escapa um valor Lua e retorna o literal SQL pronto para uso (já entre aspas quando aplicável)
function M.escape_value(value)
    if type(value) == "string" then
        -- Escape de aspas simples (duplicar) e backslashes
        local escaped = value:gsub("\\", "\\\\"):gsub("'", "''")
        -- Remove caracteres nulos que podem causar problemas.
        -- "%z" é o escape correto de byte zero em pattern Lua/LuaJIT — um
        -- "\0" literal aqui NÃO casa nada (silenciosamente vira um no-op).
        escaped = escaped:gsub("%z", "")
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
        local str = tostring(value):gsub("\\", "\\\\"):gsub("'", "''"):gsub("%z", "")
        return "'" .. str .. "'"
    end
end

-- Escapa um identificador (nome de coluna/tabela) envolvendo em backticks.
-- Suporta identificadores qualificados ("tabela.coluna" -> `tabela`.`coluna`).
-- Cada segmento é validado contra uma whitelist (letras/números/underscore);
-- identificadores fora desse formato são rejeitados com erro em vez de
-- silenciosamente aceitos entre backticks.
function M.escape_identifier(identifier)
    if type(identifier) ~= "string" or identifier == "" then
        error("Invalid SQL identifier: " .. tostring(identifier))
    end

    local parts = {}
    for part in identifier:gmatch("[^.]+") do
        if not part:match("^[%w_]+$") then
            error("Invalid SQL identifier segment: " .. part)
        end
        table.insert(parts, "`" .. part .. "`")
    end
    if #parts == 0 then
        error("Invalid SQL identifier: " .. identifier)
    end
    return table.concat(parts, ".")
end

return M
