local Validation = {}
Validation.__index = Validation

local function utf8_length(value)
    local length = 0
    for index = 1, #value do
        local byte = value:byte(index)
        if byte < 0x80 or byte >= 0xC0 then length = length + 1 end
    end
    return length
end

local function add_error(errors, field, code, message)
    errors[field] = errors[field] or {}
    errors[field][#errors[field] + 1] = { code = code, message = message }
end

local function is_empty(value)
    return value == nil or value == ""
end

local function validate_field(errors, field, value, rules)
    if rules.required and is_empty(value) then
        add_error(errors, field, "required", field .. " is required")
        return
    end
    if is_empty(value) then return end

    if rules.type and type(value) ~= rules.type then
        add_error(errors, field, "type", field .. " must be a " .. rules.type)
        return
    end

    if rules.string and type(value) ~= "string" then
        add_error(errors, field, "string", field .. " must be a string")
    elseif rules.number and type(value) ~= "number" then
        add_error(errors, field, "number", field .. " must be a number")
    end

    if type(value) == "string" then
        local length = utf8_length(value)
        if rules.min_length and length < rules.min_length then
            add_error(errors, field, "min_length", field .. " must be at least " .. rules.min_length .. " characters")
        end
        if rules.max_length and length > rules.max_length then
            add_error(errors, field, "max_length", field .. " must be at most " .. rules.max_length .. " characters")
        end
        if rules.length and length ~= rules.length then
            add_error(errors, field, "length", field .. " must be " .. rules.length .. " characters")
        end
        if rules.email and not value:match("^[%w._%+-]+@[%w.-]+%.%w+$") then
            add_error(errors, field, "email", field .. " must be a valid email")
        end
        if rules.format and not value:match(rules.format) then
            add_error(errors, field, "format", field .. " has an invalid format")
        end
    end

    if type(value) == "number" then
        if rules.min and value < rules.min then
            add_error(errors, field, "min", field .. " must be at least " .. rules.min)
        end
        if rules.max and value > rules.max then
            add_error(errors, field, "max", field .. " must be at most " .. rules.max)
        end
        if rules.range and (value < rules.range[1] or value > rules.range[2]) then
            add_error(errors, field, "range", field .. " must be between " .. rules.range[1] .. " and " .. rules.range[2])
        end
    end

    if rules.custom then
        local ok, result, message = pcall(rules.custom, value)
        if not ok then
            add_error(errors, field, "custom", field .. " failed custom validation")
        elseif not result then
            add_error(errors, field, "custom", message or (field .. " is invalid"))
        end
    end
end

function Validation.new(schema)
    return setmetatable({ schema = schema or {} }, Validation)
end

function Validation:_validate(data)
    if type(data) ~= "table" then
        return false, { _ = { { code = "type", message = "input must be a table" } } }
    end
    local errors = {}
    for field, rules in pairs(self.schema) do
        if type(rules) ~= "table" then error("validation rules for " .. field .. " must be a table", 2) end
        validate_field(errors, field, data[field], rules)
    end
    return next(errors) == nil, errors
end

function Validation.validate(target, schema)
    if getmetatable(target) == Validation then
        return target:_validate(schema)
    end
    return Validation.new(schema):_validate(target)
end

return Validation