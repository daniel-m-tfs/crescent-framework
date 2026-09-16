-- crescent/database/model/relations.lua
-- Relações do Active Record ORM, misturadas em Model via mixin
-- (crescent/database/model.lua faz: for k,v in pairs(relations) do Model[k]=v end)

local M = {}

-- Plurais irregulares mais comuns em nomes de tabela em inglês. Cobre os
-- casos citados na auditoria (people, categories, addresses); não é um
-- singularizador linguisticamente completo, é uma heurística de convenção.
local IRREGULAR_PLURALS = {
    people = "person",
    men = "man",
    women = "woman",
    children = "child",
    feet = "foot",
    teeth = "tooth",
    mice = "mouse",
    geese = "goose",
}

-- Deriva o nome singular de uma tabela pra usar como prefixo de FK
-- (ex: "users" -> "user_id"). A versão anterior só cortava o último
-- caractere assumindo terminação em "s" (quebrava em "categories" ->
-- "categorie_id", "addresses" -> "addresse_id", "people" -> "peopl_id").
local function singularize(word)
    if IRREGULAR_PLURALS[word] then
        return IRREGULAR_PLURALS[word]
    end
    if word:match("ies$") then
        return word:sub(1, -4) .. "y" -- categories -> category
    end
    if word:match("[sx]es$") or word:match("[cs]hes$") then
        return word:sub(1, -3) -- addresses -> address, boxes -> box, churches -> church
    end
    if word:match("s$") and not word:match("ss$") then
        return word:sub(1, -2) -- users -> user
    end
    return word
end

local function default_foreign_key(table_name)
    return singularize(table_name) .. "_id"
end

-- Hidrata um QueryBuilder já filtrado em instâncias reais do RelatedModel,
-- em vez de devolver linhas cruas ou o QueryBuilder não executado — antes,
-- hasMany/hasOne/belongsTo devolviam três formatos incompatíveis de
-- resultado (QueryBuilder, tabela crua, instância de Model).
local function hydrate_query(RelatedModel, query)
    local results, err = query:get()
    if err then
        return nil, err
    end
    return RelatedModel:_hydrate(results)
end

-- Has Many — retorna array de instâncias do RelatedModel (nunca um
-- QueryBuilder não executado nem linhas cruas)
function M.hasMany(self, RelatedModel, foreign_key, local_key)
    local_key = local_key or self._primary_key
    foreign_key = foreign_key or default_foreign_key(self._table)

    local local_value = self._attributes[local_key]
    if local_value == nil then
        return {}
    end
    local query = RelatedModel:query():where(foreign_key, local_value)

    return hydrate_query(RelatedModel, query)
end

-- Has One — retorna uma instância do RelatedModel (ou nil), nunca uma
-- linha crua. Antes delegava pra hasMany():first(), que operava sobre o
-- QueryBuilder cru e retornava uma tabela sem hidratação nenhuma.
function M.hasOne(self, RelatedModel, foreign_key, local_key)
    local_key = local_key or self._primary_key
    foreign_key = foreign_key or default_foreign_key(self._table)

    local local_value = self._attributes[local_key]
    if local_value == nil then
        return nil
    end
    local result, err = RelatedModel:query():where(foreign_key, local_value):first()
    if err or not result then
        return nil, err
    end

    local instance = RelatedModel:new(result)
    instance._original = RelatedModel:_copyTable(result)
    instance._exists = true
    return instance
end

-- Belongs To — já retornava instância hidratada via RelatedModel:find();
-- só corrige a mesma singularização ingênua do foreign_key default.
function M.belongsTo(self, RelatedModel, foreign_key, owner_key)
    owner_key = owner_key or RelatedModel._primary_key
    foreign_key = foreign_key or default_foreign_key(RelatedModel._table)

    local foreign_value = self._attributes[foreign_key]

    return RelatedModel:find(foreign_value)
end

return M
