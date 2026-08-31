-- crescent/database/model/validation.lua
-- Validações do Active Record ORM, misturadas em Model via mixin
-- (crescent/database/model.lua faz: for k,v in pairs(validation) do Model[k]=v end)

local M = {}

function M.validate(self)
    if not self._validates or not next(self._validates) then
        return true
    end

    local errors = {}

    for field, rules in pairs(self._validates) do
        local value = self._attributes[field]

        -- Required
        if rules.required and (not value or value == "") then
            errors[field] = field .. " is required"
        end

        -- Min length
        if rules.min_length and value and #tostring(value) < rules.min_length then
            errors[field] = field .. " must be at least " .. rules.min_length .. " characters"
        end

        -- Max length
        if rules.max_length and value and #tostring(value) > rules.max_length then
            errors[field] = field .. " must be at most " .. rules.max_length .. " characters"
        end

        -- Email
        if rules.email and value then
            if not string.match(value, "^[%w._%+-]+@[%w.-]+%.%w+$") then
                errors[field] = field .. " must be a valid email"
            end
        end

        -- Unique (verifica no banco)
        if rules.unique and value then
            local query = self:query():where(field, value)

            -- Se está atualizando, ignora o próprio registro
            if self._exists then
                local id = self._attributes[self._primary_key]
                query = query:where(self._primary_key, "!=", id)
            end

            local exists = query:first()
            if exists then
                errors[field] = field .. " already exists"
            end
        end
    end

    if next(errors) then
        return false, errors
    end

    return true
end

return M
