-- crescent/database/model.lua
-- Active Record ORM para Crescent Framework

local QueryBuilder = require("crescent.database.query_builder")

local Model = {}
Model.__index = Model

-- Cria nova classe Model
function Model:extend(config)
    local ModelClass = setmetatable({}, {__index = self})
    
    -- Configuração da tabela
    ModelClass._table = config.table or "users"
    ModelClass._primary_key = config.primary_key or "id"
    ModelClass._fillable = config.fillable or {}
    ModelClass._hidden = config.hidden or {}
    ModelClass._guarded = config.guarded or {}
    ModelClass._timestamps = config.timestamps ~= false -- default true
    ModelClass._soft_deletes = config.soft_deletes or false
    
    -- Validações
    ModelClass._validates = config.validates or {}
    
    -- Relações
    ModelClass._relations = config.relations or {}
    
    -- Hooks
    ModelClass._before_create = config.before_create
    ModelClass._after_create = config.after_create
    ModelClass._before_save = config.before_save
    ModelClass._after_save = config.after_save
    ModelClass._before_update = config.before_update
    ModelClass._after_update = config.after_update
    ModelClass._before_delete = config.before_delete
    ModelClass._after_delete = config.after_delete
    
    return ModelClass
end

-- Cria nova instância do model (não salva no DB)
function Model:new(attributes)
    local instance = setmetatable({}, {
        __index = function(t, key)
            -- Primeiro tenta acessar métodos do Model
            if self[key] then
                return self[key]
            end
            -- Senão, acessa atributos
            return rawget(t, "_attributes") and rawget(t, "_attributes")[key]
        end,
        __newindex = function(t, key, value)
            -- Propriedades internas começam com _
            if key:sub(1,1) == "_" then
                rawset(t, key, value)
            else
                -- Outros valores vão para _attributes
                local attrs = rawget(t, "_attributes")
                if attrs then
                    attrs[key] = value
                end
            end
        end
    })
    instance._attributes = attributes or {}
    instance._original = {}
    instance._exists = false
    instance._relations_loaded = {}
    return instance
end

-- ==========================
-- QUERY METHODS (Static)
-- ==========================

-- Retorna query builder para a tabela
function Model:query()
    return QueryBuilder.table(self._table)
end

-- Busca por ID
function Model:find(id)
    local result = self:query()
        :where(self._primary_key, id)
        :first()
    
    if result then
        local instance = self:new(result)
        instance._original = self:_copyTable(result)
        instance._exists = true
        return instance
    end
    
    return nil
end

-- Busca por ID ou erro
function Model:findOrFail(id)
    local instance = self:find(id)
    if not instance then
        error("Model not found with " .. self._primary_key .. " = " .. tostring(id))
    end
    return instance
end

-- Busca primeiro registro
function Model:first()
    local result = self:query():first()
    if result then
        local instance = self:new(result)
        instance._original = self:_copyTable(result)
        instance._exists = true
        return instance
    end
    return nil
end

-- Busca todos os registros
function Model:all()
    local results = self:query():get()
    return self:_hydrate(results)
end

-- WHERE
function Model:where(column, operator, value)
    -- Retorna query builder para encadeamento
    return self:query():where(column, operator, value)
end

-- Executa query SQL raw (retorna resultados brutos, não instâncias do Model)
function Model:raw(sql, bindings)
    return QueryBuilder.raw(sql, bindings)
end

-- ==========================
-- CRUD METHODS (Instance)
-- ==========================

-- Cria novo registro
function Model:create(attributes)
    local instance = self:new(attributes)
    
    -- Validações
    local valid, errors = instance:validate()
    if not valid then
        return nil, errors
    end
    
    -- Before create hook
    if self._before_create then
        self._before_create(instance)
    end
    
    -- Before save hook
    if self._before_save then
        self._before_save(instance)
    end
    
    -- Timestamps
    if self._timestamps then
        instance._attributes.created_at = os.date("%Y-%m-%d %H:%M:%S")
        instance._attributes.updated_at = os.date("%Y-%m-%d %H:%M:%S")
    end
    
    -- Filtra fillable/guarded
    local data = instance:_filterFillable(instance._attributes)
    
    -- Insere no banco
    local id, err = self:query():insert(data)
    
    if id then
        instance._attributes[self._primary_key] = id
        instance._exists = true
        instance._original = self:_copyTable(instance._attributes)
        
        -- After create hook
        if self._after_create then
            self._after_create(instance)
        end
        
        -- After save hook
        if self._after_save then
            self._after_save(instance)
        end
        
        return instance
    end
    
    return nil, err or "Failed to create record"
end

-- Salva instância (create ou update)
function Model:save()
    if self._exists then
        return self:_performUpdate()
    else
        return self:_performInsert()
    end
end

-- Atualiza registro existente
function Model:update(attributes)
    if not self._exists then
        error("Cannot update a model that doesn't exist in database")
    end
    
    -- Merge attributes
    for k, v in pairs(attributes) do
        self._attributes[k] = v
    end
    
    return self:_performUpdate()
end

-- Deleta registro
function Model:delete()
    if not self._exists then
        error("Cannot delete a model that doesn't exist in database")
    end
    
    -- Before delete hook
    if self._before_delete then
        self._before_delete(self)
    end
    
    local id = self._attributes[self._primary_key]
    
    -- Soft delete
    if self._soft_deletes then
        self._attributes.deleted_at = os.date("%Y-%m-%d %H:%M:%S")
        return self:_performUpdate()
    end
    
    -- Hard delete
    local result = self:query()
        :where(self._primary_key, id)
        :delete()
    
    if result then
        self._exists = false
        
        -- After delete hook
        if self._after_delete then
            self._after_delete(self)
        end
        
        return true
    end
    
    return false
end

-- ==========================
-- VALIDATIONS
-- ==========================

function Model:validate()
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

-- ==========================
-- RELATIONS
-- ==========================

-- Has Many
function Model:hasMany(RelatedModel, foreign_key, local_key)
    local local_key = local_key or self._primary_key
    local foreign_key = foreign_key or self._table:sub(1, -2) .. "_id" -- users -> user_id
    
    local local_value = self._attributes[local_key]
    
    return RelatedModel:query():where(foreign_key, local_value)
end

-- Has One
function Model:hasOne(RelatedModel, foreign_key, local_key)
    return self:hasMany(RelatedModel, foreign_key, local_key):first()
end

-- Belongs To
function Model:belongsTo(RelatedModel, foreign_key, owner_key)
    local owner_key = owner_key or RelatedModel._primary_key
    local foreign_key = foreign_key or RelatedModel._table:sub(1, -2) .. "_id"
    
    local foreign_value = self._attributes[foreign_key]
    
    return RelatedModel:find(foreign_value)
end

-- ==========================
-- ATTRIBUTES
-- ==========================

-- Get attribute
function Model:get(key)
    -- Verifica se é uma relação
    if self._relations[key] then
        if not self._relations_loaded[key] then
            self._relations_loaded[key] = self._relations[key](self)
        end
        return self._relations_loaded[key]
    end
    
    return self._attributes[key]
end

-- Set attribute
function Model:set(key, value)
    self._attributes[key] = value
end

-- To table (remove hidden fields)
function Model:toTable()
    local result = {}
    for k, v in pairs(self._attributes) do
        local is_hidden = false
        for _, hidden in ipairs(self._hidden) do
            if k == hidden then
                is_hidden = true
                break
            end
        end
        if not is_hidden then
            result[k] = v
        end
    end
    return result
end

-- ==========================
-- PRIVATE METHODS
-- ==========================

function Model:_performInsert()
    -- Before create hook
    if self._before_create then
        self._before_create(self)
    end
    
    -- Before save hook
    if self._before_save then
        self._before_save(self)
    end
    
    -- Timestamps
    if self._timestamps then
        self._attributes.created_at = os.date("%Y-%m-%d %H:%M:%S")
        self._attributes.updated_at = os.date("%Y-%m-%d %H:%M:%S")
    end
    
    local data = self:_filterFillable(self._attributes)
    local id = self:query():insert(data)
    
    if id then
        self._attributes[self._primary_key] = id
        self._exists = true
        self._original = self:_copyTable(self._attributes)
        
        -- After create hook
        if self._after_create then
            self._after_create(self)
        end
        
        -- After save hook
        if self._after_save then
            self._after_save(self)
        end
        
        return true
    end
    
    return false
end

function Model:_performUpdate()
    -- Before update hook
    if self._before_update then
        self._before_update(self)
    end
    
    -- Before save hook
    if self._before_save then
        self._before_save(self)
    end
    
    -- Timestamps
    if self._timestamps then
        self._attributes.updated_at = os.date("%Y-%m-%d %H:%M:%S")
    end
    
    local id = self._attributes[self._primary_key]
    local data = self:_filterFillable(self._attributes)
    
    -- Remove primary key do update
    data[self._primary_key] = nil
    
    local result = self:query()
        :where(self._primary_key, id)
        :update(data)
    
    if result then
        self._original = self:_copyTable(self._attributes)
        
        -- After update hook
        if self._after_update then
            self._after_update(self)
        end
        
        -- After save hook
        if self._after_save then
            self._after_save(self)
        end
        
        return true
    end
    
    return false
end

function Model:_filterFillable(data)
    -- Se tem guarded, remove esses campos
    if #self._guarded > 0 then
        local filtered = {}
        for k, v in pairs(data) do
            local is_guarded = false
            for _, guarded in ipairs(self._guarded) do
                if k == guarded then
                    is_guarded = true
                    break
                end
            end
            if not is_guarded then
                filtered[k] = v
            end
        end
        return filtered
    end
    
    -- Se tem fillable, só aceita esses campos
    if #self._fillable > 0 then
        local filtered = {}
        for _, field in ipairs(self._fillable) do
            if data[field] ~= nil then
                filtered[field] = data[field]
            end
        end
        return filtered
    end
    
    -- Senão, retorna tudo
    return data
end

function Model:_hydrate(results)
    if not results or #results == 0 then
        return {}
    end
    
    local instances = {}
    for _, row in ipairs(results) do
        local instance = self:new(row)
        instance._original = self:_copyTable(row)
        instance._exists = true
        table.insert(instances, instance)
    end
    
    return instances
end

function Model:_copyTable(t)
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = v
    end
    return copy
end

-- ==========================
-- SERIALIZATION
-- ==========================

-- Converte o model para array/table (remove propriedades internas)
function Model:toArray()
    local data = {}
    
    -- Copia todos os atributos
    for k, v in pairs(self._attributes) do
        -- Verifica se não está em hidden
        local is_hidden = false
        if self._hidden and #self._hidden > 0 then
            for _, hidden_field in ipairs(self._hidden) do
                if k == hidden_field then
                    is_hidden = true
                    break
                end
            end
        end
        
        if not is_hidden then
            -- Se for um Model nested, converte também
            if type(v) == "table" and v.toArray then
                data[k] = v:toArray()
            else
                data[k] = v
            end
        end
    end
    
    return data
end

-- Alias para toArray (convenção)
function Model:toJSON()
    return self:toArray()
end

return Model
