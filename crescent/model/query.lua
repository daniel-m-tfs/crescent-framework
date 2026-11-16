-- Query builder bound to a model: results are hydrated into model instances,
-- soft-deleted rows are excluded by default and relations can be eager loaded.
local QueryBuilder = require("crescent.database.query_builder")
local Sql = require("crescent.database.sql")
local Relations = require("crescent.model.relations")

local ModelQuery = setmetatable({}, { __index = QueryBuilder })
ModelQuery.__index = ModelQuery

for alias, name in pairs(QueryBuilder.CAMEL_ALIASES) do
    ModelQuery[alias] = function(self, ...) return self[name](self, ...) end
end

function ModelQuery.new(model, adapter)
    local query = QueryBuilder.new(adapter)
    query.model = model
    query.trashed = "exclude"
    query.eager = {}
    setmetatable(query, ModelQuery)
    return query:table(model.table)
end

function ModelQuery:_deleted_at()
    return Sql.identifier(self.model.table .. "." .. self.model.deleted_at_column)
end

function ModelQuery:_scope_conditions()
    if not self.model.soft_deletes or self.trashed == "with" then return nil end
    local operator = self.trashed == "only" and " IS NOT NULL" or " IS NULL"
    return { { boolean = "AND", sql = self:_deleted_at() .. operator, bindings = {} } }
end

function ModelQuery:with_trashed()
    self.trashed = "with"
    return self
end

function ModelQuery:only_trashed()
    self.trashed = "only"
    return self
end

-- with("posts", "posts.comments", { author = function(q) q:select(...) end })
function ModelQuery:with(...)
    for _, spec in ipairs({ ... }) do self.eager[#self.eager + 1] = spec end
    return self
end

function ModelQuery:get(adapter)
    adapter = self:_adapter(adapter)
    local rows, err, errno, sqlstate, kind = QueryBuilder.get(self, adapter)
    if not rows then return nil, err, errno, sqlstate, kind end
    local models = self.model:hydrate_all(rows)
    local loaded, load_err, load_errno, load_sqlstate, load_kind =
        Relations.eager_load(self.model, models, self.eager, adapter)
    if not loaded then return nil, load_err, load_errno, load_sqlstate, load_kind end
    return models
end

ModelQuery.fetch = ModelQuery.get

function ModelQuery:first(adapter)
    local previous = self.limit_value
    self.limit_value = 1
    local models, err, errno, sqlstate, kind = self:get(adapter)
    self.limit_value = previous
    if not models then return nil, err, errno, sqlstate, kind end
    return models[1]
end

function ModelQuery:find(id, adapter)
    return self:where(self.model.table .. "." .. self.model.primary_key, id):first(adapter)
end

-- Raw rows (no hydration, no eager loading).
function ModelQuery:rows(adapter)
    return QueryBuilder.get(self, adapter)
end

-- Mass delete: soft deletes become UPDATE deleted_at unless force_delete().
function ModelQuery:delete(adapter)
    if self.model.soft_deletes then
        return QueryBuilder.update(self, adapter, { [self.model.deleted_at_column] = self.model.timestamp() })
    end
    return QueryBuilder.delete(self, adapter)
end

function ModelQuery:force_delete(adapter)
    return QueryBuilder.delete(self, adapter)
end

function ModelQuery:restore(adapter)
    if not self.model.soft_deletes then return nil, "soft deletes are not enabled for this model" end
    self.trashed = "only"
    return QueryBuilder.update(self, adapter, { [self.model.deleted_at_column] = Sql.NULL })
end

ModelQuery.withTrashed = ModelQuery.with_trashed
ModelQuery.onlyTrashed = ModelQuery.only_trashed
ModelQuery.forceDelete = ModelQuery.force_delete

return ModelQuery
