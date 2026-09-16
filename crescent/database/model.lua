-- crescent/database/model.lua
-- Active Record ORM para Crescent Framework

local QueryBuilder = require("crescent.database.query_builder")
local validation = require("crescent.database.model.validation")
local relations = require("crescent.database.model.relations")

local Model = {}
Model.__index = Model

for k, v in pairs(validation) do Model[k] = v end
for k, v in pairs(relations) do Model[k] = v end

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
    attributes = attributes or {}

    -- Aviso (não bloqueia): __index abaixo dá prioridade a métodos do Model
    -- sobre atributos — uma coluna chamada "save"/"delete"/"update"/"get"/
    -- "query"/etc. fica inacessível via `instance.coluna` (sempre resolve
    -- pro método). Não dá pra simplesmente inverter essa prioridade sem
    -- risco pior (uma coluna string chamada "save" faria `instance:save()`
    -- tentar chamar uma string, quebrando toda instância). Só avisa, pra
    -- não ser uma armadilha silenciosa — use instance:get("coluna") pra
    -- essas colunas.
    for key in pairs(attributes) do
        if type(key) == "string" and self[key] ~= nil then
            print(string.format(
                "⚠️  Model:new() — atributo '%s' colide com um método do Model. " ..
                "instance.%s sempre vai resolver pro método; use instance:get('%s') para o valor da coluna.",
                key, key, key
            ))
        end
    end

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
    instance._attributes = attributes
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
        instance._attributes.created_at = os.date("!%Y-%m-%d %H:%M:%S")
        instance._attributes.updated_at = os.date("!%Y-%m-%d %H:%M:%S")
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
        self._attributes.deleted_at = os.date("!%Y-%m-%d %H:%M:%S")
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
-- ATTRIBUTES
-- ==========================

-- Get attribute
function Model:get(key)
    -- Verifica se é uma relação
    if self._relations[key] then
        if not self._relations_loaded[key] then
            -- Captura os dois retornos (resultado, erro) — hasMany/hasOne/
            -- belongsTo podem propagar erro de DB. Não cacheia em caso de
            -- erro, pra próxima chamada poder tentar de novo.
            local result, err = self._relations[key](self)
            if err then
                return nil, err
            end
            self._relations_loaded[key] = result
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
    -- Validações — antes só Model:create() validava; Model:save() num
    -- registro novo pulava validate() inteiramente e inseria qualquer
    -- coisa no banco (campo required vazio, email inválido, etc.)
    local valid, errors = self:validate()
    if not valid then
        return false, errors
    end

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
        self._attributes.created_at = os.date("!%Y-%m-%d %H:%M:%S")
        self._attributes.updated_at = os.date("!%Y-%m-%d %H:%M:%S")
    end

    local data = self:_filterFillable(self._attributes)
    local id, err = self:query():insert(data)

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

    return false, err or "Failed to insert record"
end

function Model:_performUpdate()
    -- Validações — mesma lacuna do _performInsert: Model:update()/save()
    -- num registro existente pulavam validate() inteiramente.
    local valid, errors = self:validate()
    if not valid then
        return false, errors
    end

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
        self._attributes.updated_at = os.date("!%Y-%m-%d %H:%M:%S")
    end

    local id = self._attributes[self._primary_key]
    local data = self:_filterFillable(self._attributes)

    -- Remove primary key do update
    data[self._primary_key] = nil

    local result, err = self:query()
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

    return false, err or "Failed to update record"
end

function Model:_filterFillable(data)
    local result = data

    -- Se tem guarded, remove esses campos
    if #self._guarded > 0 then
        local filtered = {}
        for k, v in pairs(result) do
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
        result = filtered
    end

    -- Se tem fillable, só aceita esses campos. Antes, configurar guarded E
    -- fillable ao mesmo tempo fazia fillable ser silenciosamente ignorado
    -- (só o branch de guarded rodava); agora os dois se combinam.
    if #self._fillable > 0 then
        local filtered = {}
        for _, field in ipairs(self._fillable) do
            if result[field] ~= nil then
                filtered[field] = result[field]
            end
        end
        result = filtered
    end

    return result
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
