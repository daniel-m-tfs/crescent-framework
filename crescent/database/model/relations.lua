-- crescent/database/model/relations.lua
-- Relações do Active Record ORM, misturadas em Model via mixin
-- (crescent/database/model.lua faz: for k,v in pairs(relations) do Model[k]=v end)

local M = {}

-- Has Many
function M.hasMany(self, RelatedModel, foreign_key, local_key)
    local local_key = local_key or self._primary_key
    local foreign_key = foreign_key or self._table:sub(1, -2) .. "_id" -- users -> user_id

    local local_value = self._attributes[local_key]

    return RelatedModel:query():where(foreign_key, local_value)
end

-- Has One
function M.hasOne(self, RelatedModel, foreign_key, local_key)
    return self:hasMany(RelatedModel, foreign_key, local_key):first()
end

-- Belongs To
function M.belongsTo(self, RelatedModel, foreign_key, owner_key)
    local owner_key = owner_key or RelatedModel._primary_key
    local foreign_key = foreign_key or RelatedModel._table:sub(1, -2) .. "_id"

    local foreign_value = self._attributes[foreign_key]

    return RelatedModel:find(foreign_value)
end

return M
