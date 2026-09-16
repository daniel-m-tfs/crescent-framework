-- crescent/database/model/validation.lua
-- Validações do Active Record ORM, misturadas em Model via mixin
-- (crescent/database/model.lua faz: for k,v in pairs(validation) do Model[k]=v end)

local M = {}

-- Conta caracteres (não bytes) de uma string UTF-8. #str conta bytes, o que
-- quebra min_length/max_length pra qualquer texto acentuado (ex: "café" tem
-- 4 caracteres mas 5 bytes, porque "é" ocupa 2 bytes em UTF-8). Só conta
-- bytes que NÃO são continuação de um caractere multi-byte (0x80-0xBF).
local function utf8_length(str)
    local len = 0
    for i = 1, #str do
        local byte = str:byte(i)
        if byte < 0x80 or byte >= 0xC0 then
            len = len + 1
        end
    end
    return len
end

function M.validate(self)
    if not self._validates or not next(self._validates) then
        return true
    end

    local errors = {}

    -- Acumula mensagens por campo em vez de sobrescrever: um campo pode
    -- falhar mais de uma regra ao mesmo tempo (ex: min_length E unique), e
    -- a versão anterior descartava todas as mensagens menos a última.
    local function add_error(field, message)
        if errors[field] then
            errors[field] = errors[field] .. "; " .. message
        else
            errors[field] = message
        end
    end

    for field, rules in pairs(self._validates) do
        local value = self._attributes[field]

        -- Required
        if rules.required and (not value or value == "") then
            add_error(field, field .. " is required")
        end

        -- Min length (conta caracteres UTF-8, não bytes — ver utf8_length)
        if rules.min_length and value and utf8_length(tostring(value)) < rules.min_length then
            add_error(field, field .. " must be at least " .. rules.min_length .. " characters")
        end

        -- Max length (idem)
        if rules.max_length and value and utf8_length(tostring(value)) > rules.max_length then
            add_error(field, field .. " must be at most " .. rules.max_length .. " characters")
        end

        -- Email
        if rules.email and value then
            if not string.match(value, "^[%w._%+-]+@[%w.-]+%.%w+$") then
                add_error(field, field .. " must be a valid email")
            end
        end

        -- Unique (verifica no banco). Nota: é uma checagem TOCTOU, não uma
        -- garantia real de unicidade — duas requisições concorrentes podem
        -- passar aqui simultaneamente. Para garantia real, crie uma
        -- constraint UNIQUE na migration da tabela.
        if rules.unique and value then
            local query = self:query():where(field, value)

            -- Se está atualizando, ignora o próprio registro
            if self._exists then
                local id = self._attributes[self._primary_key]
                query = query:where(self._primary_key, "!=", id)
            end

            local exists, query_error = query:first()
            if query_error then
                add_error(field, "could not verify uniqueness: " .. query_error)
            elseif exists then
                add_error(field, field .. " already exists")
            end
        end
    end

    if next(errors) then
        return false, errors
    end

    return true
end

return M
