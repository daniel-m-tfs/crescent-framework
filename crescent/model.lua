local Validation = require("crescent.validation")
local QueryBuilder = require("crescent.database.query_builder")

local Model = {}
Model.__index = Model

local function copy_attributes(attributes)
    local copy = {}
    for key, value in pairs(attributes or {}) do copy[key] = value end
    return copy
end

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

function Model:extend(definition)
    definition = definition or {}
    local class = setmetatable({}, { __index = self })
    class.table = definition.table or "models"
    class.primary_key = definition.primary_key or "id"
    class.fillable = definition.fillable
    class.guarded = definition.guarded or {}
    class.hidden = definition.hidden or {}
    class.timestamps = definition.timestamps == true
    class.soft_deletes = definition.soft_deletes == true
    class.validates = definition.validates or {}
    class.relations = definition.relations or {}
    return class
end

function Model:new(attributes)
    local instance = setmetatable({
        attributes = {},
        original = {},
        exists = false,
    }, {
        __index = self,
        __newindex = function(object, key, value)
            if key == "attributes" or key == "original" or key == "exists" then
                rawset(object, key, value)
            else
                object.attributes[key] = value
            end
        end,
    })
    instance:fill(attributes or {})
    if self.timestamps then instance:touch(true) end
    return instance
end

function Model:fill(attributes)
    for key, value in pairs(attributes or {}) do
        local allowed = (self.fillable == nil or contains(self.fillable, key))
            and not contains(self.guarded, key)
        if allowed then self.attributes[key] = value end
    end
    return self
end

function Model:get(key)
    return self.attributes[key]
end

function Model:set(key, value)
    self.attributes[key] = value
    return self
end

function Model:touch(initial)
    local timestamp = os.date("!%Y-%m-%d %H:%M:%S")
    if initial and self.attributes.created_at == nil then self.attributes.created_at = timestamp end
    self.attributes.updated_at = timestamp
    return self
end

function Model:delete()
    if not self.soft_deletes then
        return nil, "soft deletes are not enabled for this model"
    end
    self.attributes.deleted_at = os.date("!%Y-%m-%d %H:%M:%S")
    return true
end

function Model:restore()
    if not self.soft_deletes then
        return nil, "soft deletes are not enabled for this model"
    end
    self.attributes.deleted_at = nil
    return true
end

function Model:trashed()
    return self.soft_deletes and self.attributes.deleted_at ~= nil
end

function Model:validate(adapter)
    local valid, errors = Validation.validate(self.attributes, self.validates)
    if not valid then return false, errors end
    if not adapter then return true, errors end

    for field, rules in pairs(self.validates) do
        if rules.unique and self.attributes[field] ~= nil then
            local query = QueryBuilder.new():table(self.table):where(field, self.attributes[field])
            if self.exists and self.attributes[self.primary_key] ~= nil then
                query:where(self.primary_key, "!=", self.attributes[self.primary_key])
            end
            local rows, query_error = query:fetch(adapter)
            if rows == nil and query_error then
                errors = errors or {}
                errors[field] = errors[field] or {}
                errors[field][#errors[field] + 1] = { code = "unique_check", message = tostring(query_error) }
            elseif rows and #rows > 0 then
                errors = errors or {}
                errors[field] = errors[field] or {}
                errors[field][#errors[field] + 1] = { code = "unique", message = field .. " must be unique" }
            end
        end
    end
    return next(errors or {}) == nil, errors or {}
end

function Model:save(adapter)
    if type(adapter) ~= "table" or type(adapter.execute) ~= "function" then
        return nil, "model save requires a database adapter"
    end
    local valid, errors = self:validate(adapter)
    if not valid then return nil, errors end
    if self.timestamps then self:touch(not self.exists) end
    local query = QueryBuilder.new():table(self.table)
    local result
    if self.exists then
        local key = self.attributes[self.primary_key]
        if key == nil then return nil, "existing model requires a primary key" end
        result = query:where(self.primary_key, key):update(adapter, self.attributes)
    else
        result = query:insert(adapter, self.attributes)
        if result then
            local insert_id = type(result) == "table" and (result.insert_id or result.id) or nil
            if insert_id ~= nil then
                self.attributes[self.primary_key] = insert_id
                self.exists = true
            end
        end
    end
    return result
end

function Model:relation(name, adapter)
    local definition = self.relations[name]
    if type(definition) ~= "table" then return nil, "unknown relation: " .. tostring(name) end
    if type(adapter) ~= "table" or type(adapter.query) ~= "function" then
        return nil, "relation loading requires a database adapter"
    end
    local related_model = definition.model
    if type(related_model) ~= "table" or type(related_model.new) ~= "function" then
        return nil, "relation model is invalid"
    end

    local relation_type = definition.type
    local foreign_key = definition.foreign_key
    local local_key = definition.local_key or self.primary_key
    local value
    if relation_type == "belongs_to" then
        value = self.attributes[definition.local_key or foreign_key]
        foreign_key = definition.foreign_key or related_model.primary_key
        local_key = definition.related_key or related_model.primary_key
    else
        value = self.attributes[local_key]
    end
    if not foreign_key or value == nil then
        return relation_type == "has_many" and {} or nil
    end

    local query = QueryBuilder.new():table(related_model.table)
    query:where(relation_type == "belongs_to" and local_key or foreign_key, value)
    local rows, err = query:fetch(adapter)
    if not rows then return nil, err end
    if relation_type == "has_many" then
        local result = {}
        for _, row in ipairs(rows) do result[#result + 1] = related_model:new(row) end
        return result
    end
    return rows[1] and related_model:new(rows[1]) or nil
end

function Model:to_table()
    local result = {}
    for key, value in pairs(self.attributes) do
        if not contains(self.hidden, key) then result[key] = value end
    end
    return result
end

function Model:toTable()
    return self:to_table()
end

return Model