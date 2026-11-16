-- Active Record models on top of the query builder.
--
--   local User = Model:extend({ table = "users", fillable = { "name", "email" } })
--   local user, errors = User:create({ name = "Ada", email = "ada@example.com" })
--   local users = User:query():where("active", true):with("posts"):get()
local Validation = require("crescent.validation")
local Database = require("crescent.database")
local QueryBuilder = require("crescent.database.query_builder")
local Sql = require("crescent.database.sql")
local ModelQuery = require("crescent.model.query")
local Relations = require("crescent.model.relations")

-- `false` (not nil) defaults keep these names from falling through to
-- attribute lookup on instances.
local Model = {
    adapter = false,
    fillable = false,
    table = "models",
    primary_key = "id",
    guarded = {},
    hidden = {},
    timestamps = false,
    soft_deletes = false,
    deleted_at_column = "deleted_at",
    validates = {},
    relations = {},
}

local INSTANCE_FIELDS = { attributes = true, original = true, exists = true, related = true }

local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then return true end
    end
    return false
end

local function adapter_for(model, adapter)
    return adapter or model.adapter or nil
end

local function class_of(object)
    local mt = getmetatable(object)
    return mt and mt.model_class or object
end

local function run_hook(model, name)
    local hook = model[name]
    if type(hook) == "function" then return hook(model) end
end

local function hook_aborted(name)
    return nil, name .. " hook aborted the operation"
end

function Model.timestamp()
    return os.date("!%Y-%m-%d %H:%M:%S")
end

local NotFound = {}
NotFound.__index = NotFound
NotFound.__tostring = function(err) return err.message end

-- Raised by find_or_fail(); carries status = 404 for error handlers.
function Model.not_found(class, id)
    return setmetatable({
        status = 404,
        code = "model_not_found",
        message = string.format("%s not found with %s = %s", class.table, class.primary_key, tostring(id)),
    }, NotFound)
end

function Model.is_not_found(err)
    return getmetatable(err) == NotFound
end

local function instance_metatable(class)
    local mt = rawget(class, "__instance_mt")
    if mt then return mt end
    mt = {
        model_class = class,
        __index = function(object, key)
            local value = class[key]
            if value ~= nil then return value end
            value = rawget(object, "attributes")[key]
            if value ~= nil then return value end
            value = rawget(object, "related")[key]
            if value == false then return nil end
            return value
        end,
        __newindex = function(object, key, value)
            if INSTANCE_FIELDS[key] then
                rawset(object, key, value)
            else
                object.attributes[key] = value
            end
        end,
    }
    rawset(class, "__instance_mt", mt)
    return mt
end

-- Every definition key is copied onto the class: table, primary_key,
-- fillable, guarded, hidden, timestamps, soft_deletes, validates, relations,
-- adapter, hooks (before_save, after_create, ...) and custom methods.
function Model:extend(definition)
    definition = definition or {}
    if type(definition) ~= "table" then error("model definition must be a table", 2) end
    local class = setmetatable({}, { __index = self })
    for key, value in pairs(definition) do class[key] = value end
    local ok, err = pcall(Sql.identifier, class.table)
    if not ok then error("model table: " .. err, 2) end
    if type(class.primary_key) ~= "string" then error("model primary_key must be a string", 2) end
    return class
end

local function blank(class, attributes, exists)
    return setmetatable({
        attributes = attributes,
        original = exists and copy(attributes) or {},
        exists = exists,
        related = {},
    }, instance_metatable(class))
end

-- New, unsaved instance. Mass assignment honours fillable/guarded.
function Model:new(attributes)
    local class = class_of(self)
    local instance = blank(class, {}, false)
    instance:fill(attributes or {})
    if class.timestamps then instance:touch(true) end
    return instance
end

-- Instance for a row read from the database: bypasses fillable, exists = true.
-- lua-resty-mysql returns BIGINT columns as strings (they may exceed 2^53),
-- so ids would be numbers after an INSERT but strings after a SELECT. On
-- hydrate, the primary key and `*_id` columns holding a canonical integer
-- that fits in a double become numbers. `casts = { column = "string" |
-- "number" | "integer" | "boolean" }` overrides this per column (e.g. keep
-- an `external_id` VARCHAR as text).
local function canonical_integer(value)
    if type(value) == "string" and #value <= 15 and (value == "0" or value:match("^%-?[1-9]%d*$")) then
        return tonumber(value)
    end
    return nil
end

local CASTS = {
    string = function(value) return tostring(value) end,
    number = function(value) return tonumber(value) or value end,
    integer = function(value) return canonical_integer(value) or value end,
    boolean = function(value)
        if value == 1 or value == "1" or value == true then return true end
        if value == 0 or value == "0" or value == false then return false end
        return value
    end,
}

local function cast_attributes(class, attributes)
    local casts = class.casts or {}
    for column, value in pairs(attributes) do
        if value ~= nil and value ~= Sql.NULL then
            local cast = casts[column]
            if cast then
                local convert = CASTS[cast]
                if not convert then error("unknown cast '" .. tostring(cast) .. "' for " .. column, 0) end
                attributes[column] = convert(value)
            elseif column == class.primary_key or (type(column) == "string" and column:match("_id$")) then
                attributes[column] = canonical_integer(value) or value
            end
        end
    end
    return attributes
end

function Model:hydrate(row)
    local class = class_of(self)
    return blank(class, cast_attributes(class, copy(row)), true)
end

function Model:hydrate_all(rows)
    local models = {}
    for index, row in ipairs(rows or {}) do models[index] = self:hydrate(row) end
    return models
end

-- ===== class methods =====

function Model:query(adapter)
    local class = class_of(self)
    return ModelQuery.new(class, adapter_for(class, adapter))
end

function Model:where(...)
    return self:query():where(...)
end

function Model:with(...)
    return self:query():with(...)
end

function Model:with_trashed()
    return self:query():with_trashed()
end

function Model:only_trashed()
    return self:query():only_trashed()
end

function Model:find(id, adapter)
    if id == nil then return nil end
    return self:query(adapter):find(id)
end

function Model:find_or_fail(id, adapter)
    local model, err = self:find(id, adapter)
    if err then error(err, 2) end
    if not model then error(Model.not_found(class_of(self), id), 2) end
    return model
end

function Model:first(adapter)
    return self:query(adapter):first()
end

function Model:all(adapter)
    return self:query(adapter):get()
end

function Model:count(adapter)
    return self:query(adapter):count()
end

-- Model:page(ctx.query.page, ctx.query.per_page) -> { data = models, meta = {...} }
function Model:page(page, per_page, options, adapter)
    return self:query(adapter):page(page, per_page, options)
end

-- Raw rows; use Model:hydrate_all() to turn them into instances.
function Model:raw(sql, bindings, adapter)
    return QueryBuilder.raw(sql, bindings, adapter_for(class_of(self), adapter))
end

function Model:create(attributes, adapter)
    local instance = self:new(attributes)
    local ok, err, errno, sqlstate, kind = instance:save(adapter)
    if not ok then return nil, err, errno, sqlstate, kind end
    return instance
end

-- ===== attributes =====

function Model:fill(attributes)
    for key, value in pairs(attributes or {}) do
        local allowed = (not self.fillable or contains(self.fillable, key))
            and not contains(self.guarded, key)
        if allowed then self.attributes[key] = value end
    end
    return self
end

-- Attribute value, or a relation (lazy-loaded on first access).
function Model:get(key)
    local value = self.attributes[key]
    if value ~= nil then return value end
    if self.relations[key] ~= nil then
        local loaded = self.related[key]
        if loaded == nil then
            local ok, err, errno, sqlstate, kind = self:load(key)
            if not ok then return nil, err, errno, sqlstate, kind end
            loaded = self.related[key]
        end
        if loaded == false then return nil end
        return loaded
    end
    return nil
end

function Model:set(key, value)
    self.attributes[key] = value
    return self
end

function Model:get_dirty()
    local dirty = {}
    for key, value in pairs(self.attributes) do
        if self.original[key] ~= value then dirty[key] = value end
    end
    for key in pairs(self.original) do
        if self.attributes[key] == nil then dirty[key] = Sql.NULL end
    end
    return dirty
end

function Model:is_dirty(key)
    local dirty = self:get_dirty()
    if key ~= nil then return dirty[key] ~= nil end
    return next(dirty) ~= nil
end

function Model:touch(initial)
    local timestamp = self.timestamp()
    if initial and self.attributes.created_at == nil then self.attributes.created_at = timestamp end
    self.attributes.updated_at = timestamp
    return self
end

function Model:trashed()
    return self.soft_deletes and self.attributes[self.deleted_at_column] ~= nil
end

-- ===== validation =====

local function add_error(errors, field, code, message)
    errors[field] = errors[field] or {}
    errors[field][#errors[field] + 1] = { code = code, message = message }
end

-- Runs crescent.validation rules plus `unique = true`, which is checked with
-- a query when a database is available. The unique check is advisory (race
-- prone): keep a UNIQUE index too; its violation is mapped by save().
function Model:validate(adapter)
    local _, errors = Validation.validate(self.attributes, self.validates)
    errors = errors or {}
    local db = Database.resolve(adapter_for(self, adapter), true)
    if db then
        local key = self.primary_key
        for field, rules in pairs(self.validates) do
            local value = self.attributes[field]
            local needs_check = rules.unique and not Sql.is_null(value) and errors[field] == nil
                and (not self.exists or self.original[field] ~= value)
            if needs_check then
                local query = QueryBuilder.new(db):table(self.table):select(key):where(field, value)
                if self.exists and self.original[key] ~= nil then query:where(key, "!=", self.original[key]) end
                local row, query_err = query:first()
                if query_err then
                    add_error(errors, field, "unique_check", "could not verify uniqueness: " .. tostring(query_err))
                elseif row then
                    add_error(errors, field, "unique", field .. " has already been taken")
                end
            end
        end
    end
    return next(errors) == nil, errors
end

-- ===== persistence =====

local function unique_field(model, message)
    local key = tostring(message or ""):match("for key '([^']+)'")
    if key then
        local candidates = {
            key, key:match("%.([^%.]+)$"),
            (key:match("([^%.]+)$") or key):gsub("^" .. model.table .. "_", ""):gsub("_unique$", ""),
        }
        for _, candidate in ipairs(candidates) do
            if candidate and (model.attributes[candidate] ~= nil or model.validates[candidate]) then
                return candidate
            end
        end
    end
    return "_database"
end

local function persistence_error(model, err, errno, sqlstate, kind)
    if kind == "unique_violation" or errno == 1062 or errno == 1586 then
        local field = unique_field(model, err)
        local message = field == "_database" and "a unique constraint was violated" or field .. " has already been taken"
        return nil, { [field] = { { code = "unique", message = message } } }
    end
    return nil, err, errno, sqlstate, kind
end

local function key_query(model, db)
    local key = model.primary_key
    local value = model.original[key]
    if value == nil then value = model.attributes[key] end
    if value == nil then return nil end
    return QueryBuilder.new(db):table(model.table):where(key, value)
end

local function perform_insert(model, db)
    if model.timestamps then model:touch(true) end
    local values = {}
    for key, value in pairs(model.attributes) do values[key] = value end
    if next(values) == nil then return nil, "cannot insert an empty model" end
    local result, err, errno, sqlstate, kind = QueryBuilder.new(db):table(model.table):insert(values)
    if not result then return persistence_error(model, err, errno, sqlstate, kind) end
    local key = model.primary_key
    local insert_id = type(result) == "table" and result.insert_id or nil
    if model.attributes[key] == nil and insert_id ~= nil and insert_id ~= 0 then
        model.attributes[key] = insert_id
    end
    model.exists = true
    model.original = copy(model.attributes)
    return true
end

local function perform_update(model, db)
    local dirty = model:get_dirty()
    dirty[model.primary_key] = nil
    if next(dirty) == nil then return true end
    if model.timestamps then
        model.attributes.updated_at = model.timestamp()
        dirty.updated_at = model.attributes.updated_at
    end
    local query = key_query(model, db)
    if not query then return nil, "existing model requires a primary key" end
    local result, err, errno, sqlstate, kind = query:update(dirty)
    if not result then return persistence_error(model, err, errno, sqlstate, kind) end
    local key_value = model.original[model.primary_key]
    model.original = copy(model.attributes)
    if key_value ~= nil then
        model.original[model.primary_key] = key_value
        model.attributes[model.primary_key] = key_value
    end
    return true
end

-- INSERT when new, UPDATE of the changed columns otherwise (never the primary
-- key). Returns the model, or nil and validation errors / a database error.
-- A before_* hook returning false aborts the operation.
function Model:save(adapter)
    local db = Database.resolve(adapter_for(self, adapter))
    local valid, errors = self:validate(db)
    if not valid then return nil, errors end

    local creating = not self.exists
    if run_hook(self, "before_save") == false then return hook_aborted("before_save") end
    local before = creating and "before_create" or "before_update"
    if run_hook(self, before) == false then return hook_aborted(before) end

    local ok, err, errno, sqlstate, kind
    if creating then
        ok, err, errno, sqlstate, kind = perform_insert(self, db)
    else
        ok, err, errno, sqlstate, kind = perform_update(self, db)
    end
    if not ok then return nil, err, errno, sqlstate, kind end

    run_hook(self, creating and "after_create" or "after_update")
    run_hook(self, "after_save")
    return self
end

-- Mass-assigns (fillable/guarded apply) and saves an existing model.
function Model:update(attributes, adapter)
    if not self.exists then return nil, "cannot update a model that does not exist in the database" end
    self:fill(attributes or {})
    return self:save(adapter)
end

local function hard_delete(model, db)
    local query = key_query(model, db)
    if not query then return nil, "model requires a primary key" end
    local result, err, errno, sqlstate, kind = query:delete()
    if not result then return nil, err, errno, sqlstate, kind end
    model.exists = false
    return true
end

local function set_deleted_at(model, db, value)
    local query = key_query(model, db)
    if not query then return nil, "model requires a primary key" end
    local column = model.deleted_at_column
    local result, err, errno, sqlstate, kind = query:update({ [column] = value == nil and Sql.NULL or value })
    if not result then return nil, err, errno, sqlstate, kind end
    model.attributes[column] = value
    model.original[column] = value
    return true
end

-- Soft delete (UPDATE deleted_at) when enabled, otherwise DELETE.
function Model:delete(adapter)
    if not self.exists then return nil, "cannot delete a model that does not exist in the database" end
    local db = Database.resolve(adapter_for(self, adapter))
    if run_hook(self, "before_delete") == false then return hook_aborted("before_delete") end
    local ok, err, errno, sqlstate, kind
    if self.soft_deletes then
        ok, err, errno, sqlstate, kind = set_deleted_at(self, db, self.timestamp())
    else
        ok, err, errno, sqlstate, kind = hard_delete(self, db)
    end
    if not ok then return nil, err, errno, sqlstate, kind end
    run_hook(self, "after_delete")
    return true
end

function Model:force_delete(adapter)
    if not self.exists then return nil, "cannot delete a model that does not exist in the database" end
    local db = Database.resolve(adapter_for(self, adapter))
    if run_hook(self, "before_delete") == false then return hook_aborted("before_delete") end
    local ok, err, errno, sqlstate, kind = hard_delete(self, db)
    if not ok then return nil, err, errno, sqlstate, kind end
    run_hook(self, "after_delete")
    return true
end

function Model:restore(adapter)
    if not self.soft_deletes then return nil, "soft deletes are not enabled for this model" end
    if not self.exists then return nil, "cannot restore a model that does not exist in the database" end
    return set_deleted_at(self, Database.resolve(adapter_for(self, adapter)), nil)
end

-- ===== relations =====

-- load("posts", "posts.comments") or load(adapter, "posts"); one query per relation.
function Model:load(...)
    local specs = { ... }
    local adapter
    if type(specs[1]) == "table" and type(specs[1].query) == "function" then adapter = table.remove(specs, 1) end
    return Relations.eager_load(class_of(self), { self }, specs, adapter_for(self, adapter))
end

function Model:relation(name, adapter)
    local ok, err, errno, sqlstate, kind = Relations.load(class_of(self), { self }, name, nil, adapter_for(self, adapter))
    if not ok then return nil, err, errno, sqlstate, kind end
    local value = self.related[name]
    if value == false then return nil end
    return value
end

-- ===== serialization =====

local function serialize(value)
    if type(value) == "table" and getmetatable(value) and type(value.to_table) == "function" and rawget(value, "attributes") then
        return value:to_table()
    end
    if type(value) == "table" then
        local list = {}
        for index, item in ipairs(value) do list[index] = serialize(item) end
        return list
    end
    return value
end

-- Attributes minus `hidden`, plus loaded relations.
function Model:to_table()
    local result = {}
    for key, value in pairs(self.attributes) do
        if not contains(self.hidden, key) then result[key] = value end
    end
    for name, value in pairs(self.related) do
        if value ~= false and not contains(self.hidden, name) then result[name] = serialize(value) end
    end
    return result
end

local CAMEL_ALIASES = {
    findOrFail = "find_or_fail",
    withTrashed = "with_trashed",
    onlyTrashed = "only_trashed",
    forceDelete = "force_delete",
    toTable = "to_table",
    toArray = "to_table",
    toJSON = "to_table",
    isDirty = "is_dirty",
    getDirty = "get_dirty",
}

for alias, name in pairs(CAMEL_ALIASES) do
    Model[alias] = function(self, ...) return self[name](self, ...) end
end

return Model
