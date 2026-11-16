-- Fluent SQL builder. SQL text and bindings are always kept separate: values
-- only ever travel as `?` bindings and identifiers are allowlisted.
local Sql = require("crescent.database.sql")

local QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

local OPERATORS = {
    ["="] = true, ["!="] = true, ["<>"] = true,
    ["<"] = true, ["<="] = true, [">"] = true, [">="] = true,
    ["LIKE"] = true, ["NOT LIKE"] = true,
}

local JOIN_OPERATORS = {
    ["="] = true, ["!="] = true, ["<>"] = true,
    ["<"] = true, ["<="] = true, [">"] = true, [">="] = true,
}

local function identifier(value)
    local ok, result = pcall(Sql.identifier, value)
    if not ok then error(result, 3) end
    return result
end

local function non_negative_integer(value, name)
    if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
        error(name .. " must be a non-negative integer", 3)
    end
    return value
end

local function positive_integer(value, name)
    if type(value) ~= "number" or value < 1 or value ~= math.floor(value) then
        error(name .. " must be a positive integer", 3)
    end
    return value
end

local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do
        if type(key) ~= "string" then error("column names must be strings", 3) end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

local function append(target, values)
    for index = 1, #values do target[#target + 1] = values[index] end
    return target
end

local function is_adapter(value)
    return type(value) == "table" and type(value.query) == "function"
end

local function operator_of(operator)
    operator = type(operator) == "string" and operator:upper() or ""
    if not OPERATORS[operator] then error("invalid SQL operator: " .. tostring(operator), 4) end
    return operator
end

-- Static `QueryBuilder.table("users")` or instance `builder:table("users")`.
function QueryBuilder.new(adapter)
    return setmetatable({
        adapter = adapter,
        table_name = nil,
        columns = { "*" },
        joins = {},
        conditions = {},
        orders = {},
        limit_value = nil,
        offset_value = nil,
    }, QueryBuilder)
end

function QueryBuilder.table(self, name)
    if type(self) == "string" then return QueryBuilder.new(name):table(self) end
    self.table_name = identifier(name)
    return self
end

function QueryBuilder:from(name)
    return self:table(name)
end

function QueryBuilder:using(adapter)
    self.adapter = adapter
    return self
end

function QueryBuilder:select(...)
    local values = { ... }
    if #values == 0 then error("select requires at least one column", 2) end
    self.columns = {}
    for _, value in ipairs(values) do
        local ok, column = pcall(Sql.select_identifier, value)
        if not ok then error(column, 2) end
        self.columns[#self.columns + 1] = column
    end
    return self
end

function QueryBuilder:_add(boolean, sql, bindings)
    self.conditions[#self.conditions + 1] = { boolean = boolean, sql = sql, bindings = bindings or {} }
    return self
end

local function compile_conditions(conditions)
    local parts, bindings, has_or = {}, {}, false
    for index, condition in ipairs(conditions) do
        if index > 1 then
            parts[#parts + 1] = condition.boolean
            if condition.boolean == "OR" then has_or = true end
        end
        parts[#parts + 1] = condition.sql
        append(bindings, condition.bindings)
    end
    return table.concat(parts, " "), bindings, has_or
end

-- where(column, value), where(column, operator, value) or where(function(q) ... end)
local function add_where(self, boolean, column, ...)
    if type(column) == "function" then
        local group = QueryBuilder.new()
        column(group)
        if #group.conditions == 0 then return self end
        local sql, bindings = compile_conditions(group.conditions)
        return self:_add(boolean, "(" .. sql .. ")", bindings)
    end
    local column_sql = identifier(column)
    local operator, value
    if select("#", ...) >= 2 then
        operator, value = ...
    else
        operator, value = "=", ...
    end
    operator = operator_of(operator)
    if Sql.is_null(value) then
        if operator == "=" then return self:_add(boolean, column_sql .. " IS NULL") end
        if operator == "!=" or operator == "<>" then return self:_add(boolean, column_sql .. " IS NOT NULL") end
        error("operator " .. operator .. " cannot compare with NULL", 3)
    end
    return self:_add(boolean, column_sql .. " " .. operator .. " ?", { value })
end

function QueryBuilder:where(column, ...)
    return add_where(self, "AND", column, ...)
end

function QueryBuilder:or_where(column, ...)
    return add_where(self, "OR", column, ...)
end

function QueryBuilder:where_null(column)
    return self:_add("AND", identifier(column) .. " IS NULL")
end

function QueryBuilder:or_where_null(column)
    return self:_add("OR", identifier(column) .. " IS NULL")
end

function QueryBuilder:where_not_null(column)
    return self:_add("AND", identifier(column) .. " IS NOT NULL")
end

function QueryBuilder:or_where_not_null(column)
    return self:_add("OR", identifier(column) .. " IS NOT NULL")
end

local function add_in(self, boolean, column, values, negate)
    if type(values) ~= "table" then error("where_in values must be a table", 3) end
    local column_sql = identifier(column)
    if #values == 0 then return self:_add(boolean, negate and "1 = 1" or "1 = 0") end
    local placeholders, bindings = {}, {}
    for index = 1, #values do
        if Sql.is_null(values[index]) then error("where_in values cannot contain NULL", 3) end
        placeholders[index] = "?"
        bindings[index] = values[index]
    end
    local keyword = negate and " NOT IN (" or " IN ("
    return self:_add(boolean, column_sql .. keyword .. table.concat(placeholders, ", ") .. ")", bindings)
end

function QueryBuilder:where_in(column, values)
    return add_in(self, "AND", column, values, false)
end

function QueryBuilder:or_where_in(column, values)
    return add_in(self, "OR", column, values, false)
end

function QueryBuilder:where_not_in(column, values)
    return add_in(self, "AND", column, values, true)
end

-- Escape hatch for expressions the builder cannot express. Values must still
-- go through `?` bindings.
function QueryBuilder:where_raw(sql, bindings)
    if type(sql) ~= "string" or sql == "" then error("where_raw requires SQL", 2) end
    return self:_add("AND", "(" .. sql .. ")", bindings)
end

function QueryBuilder:or_where_raw(sql, bindings)
    if type(sql) ~= "string" or sql == "" then error("or_where_raw requires SQL", 2) end
    return self:_add("OR", "(" .. sql .. ")", bindings)
end

local function add_join(self, kind, name, first, operator, second)
    if second == nil then operator, second = "=", operator end
    operator = type(operator) == "string" and operator:upper() or ""
    if not JOIN_OPERATORS[operator] then error("invalid SQL operator: " .. tostring(operator), 3) end
    self.joins[#self.joins + 1] = string.format("%s JOIN %s ON %s %s %s",
        kind, identifier(name), identifier(first), operator, identifier(second))
    return self
end

function QueryBuilder:join(name, first, operator, second)
    return add_join(self, "INNER", name, first, operator, second)
end

function QueryBuilder:left_join(name, first, operator, second)
    return add_join(self, "LEFT", name, first, operator, second)
end

function QueryBuilder:right_join(name, first, operator, second)
    return add_join(self, "RIGHT", name, first, operator, second)
end

function QueryBuilder:order_by(column, direction)
    direction = type(direction) == "string" and direction:upper() or "ASC"
    if direction ~= "ASC" and direction ~= "DESC" then
        error("order direction must be ASC or DESC", 2)
    end
    self.orders[#self.orders + 1] = identifier(column) .. " " .. direction
    return self
end

function QueryBuilder:limit(value)
    self.limit_value = non_negative_integer(value, "limit")
    return self
end

function QueryBuilder:offset(value)
    self.offset_value = non_negative_integer(value, "offset")
    return self
end

QueryBuilder.take = QueryBuilder.limit
QueryBuilder.skip = QueryBuilder.offset

-- Sets LIMIT/OFFSET for a 1-based page.
function QueryBuilder:paginate(page, per_page)
    page = positive_integer(page or 1, "page")
    per_page = positive_integer(per_page or 15, "per_page")
    self.limit_value = per_page
    self.offset_value = (page - 1) * per_page
    return self
end

QueryBuilder.MAX_PER_PAGE = 100

-- Lenient parsing for values that usually come from the query string:
-- anything that is not a positive integer falls back to the default.
local function page_number(value, default)
    value = tonumber(value)
    if not value or value < 1 or value ~= math.floor(value) then return default end
    return value
end

-- Runs a COUNT plus the page query and returns
-- `{ data = rows_or_models, meta = { page, per_page, total, last_page, from, to } }`.
-- `per_page` is capped at `options.max_per_page` (default MAX_PER_PAGE) so a
-- client cannot request the whole table.
function QueryBuilder:page(page, per_page, options, adapter)
    if is_adapter(options) then options, adapter = nil, options end
    options = options or {}
    local max_per_page = options.max_per_page or QueryBuilder.MAX_PER_PAGE
    page = page_number(page, 1)
    per_page = math.min(page_number(per_page, options.default_per_page or 15), max_per_page)

    local total, err, errno, sqlstate, kind = self:count(adapter)
    if total == nil then return nil, err, errno, sqlstate, kind end
    local last_page = math.max(1, math.ceil(total / per_page))

    local previous_limit, previous_offset = self.limit_value, self.offset_value
    self.limit_value, self.offset_value = per_page, (page - 1) * per_page
    local data
    data, err, errno, sqlstate, kind = self:get(adapter)
    self.limit_value, self.offset_value = previous_limit, previous_offset
    if not data then return nil, err, errno, sqlstate, kind end

    local from = #data > 0 and (page - 1) * per_page + 1 or nil
    return {
        data = data,
        meta = {
            page = page,
            per_page = per_page,
            total = total,
            last_page = last_page,
            from = from,
            to = from and from + #data - 1 or nil,
        },
    }
end

-- Conditions added implicitly (e.g. soft-delete scopes). Always ANDed with
-- the user conditions and never counted as a WHERE for update/delete.
function QueryBuilder:_scope_conditions()
    return nil
end

function QueryBuilder:_where_sql()
    local sql, bindings, has_or = compile_conditions(self.conditions)
    local scopes = self:_scope_conditions()
    if scopes and #scopes > 0 then
        local scope_sql, scope_bindings = compile_conditions(scopes)
        if sql == "" then
            sql = scope_sql
        else
            if has_or then sql = "(" .. sql .. ")" end
            sql = sql .. " AND " .. scope_sql
        end
        append(bindings, scope_bindings)
    end
    return sql, bindings
end

function QueryBuilder:_require_table()
    if not self.table_name then error("query requires a table", 3) end
end

-- options.columns, options.limit override the builder state without mutating it.
function QueryBuilder:_select_sql(options)
    options = options or {}
    self:_require_table()
    local parts = { "SELECT " .. (options.columns or table.concat(self.columns, ", ")) .. " FROM " .. self.table_name }
    for _, join in ipairs(self.joins) do parts[#parts + 1] = join end
    local where_sql, bindings = self:_where_sql()
    if where_sql ~= "" then parts[#parts + 1] = "WHERE " .. where_sql end
    if not options.aggregate then
        if #self.orders > 0 then parts[#parts + 1] = "ORDER BY " .. table.concat(self.orders, ", ") end
        local limit = options.limit or self.limit_value
        if limit then parts[#parts + 1] = "LIMIT " .. limit end
        if self.offset_value then parts[#parts + 1] = "OFFSET " .. self.offset_value end
    end
    return table.concat(parts, " "), bindings
end

function QueryBuilder:to_sql()
    return self:_select_sql()
end

function QueryBuilder:to_count_sql()
    return self:_select_sql({ columns = "COUNT(*) AS `aggregate`", aggregate = true })
end

-- values: { column = value } or an array of such rows (multi-row insert).
function QueryBuilder:to_insert(values)
    self:_require_table()
    if type(values) ~= "table" or next(values) == nil then error("insert requires values", 2) end
    local rows = type(values[1]) == "table" and values or { values }
    local seen, keys = {}, {}
    for _, row in ipairs(rows) do
        for _, key in ipairs(sorted_keys(row)) do
            if not seen[key] then seen[key] = true keys[#keys + 1] = key end
        end
    end
    if #keys == 0 then error("insert requires values", 2) end
    table.sort(keys)
    local columns, tuples, bindings = {}, {}, {}
    for index, key in ipairs(keys) do columns[index] = identifier(key) end
    for _, row in ipairs(rows) do
        local placeholders = {}
        for index, key in ipairs(keys) do
            if row[key] == nil then
                placeholders[index] = "NULL"
            else
                placeholders[index] = "?"
                bindings[#bindings + 1] = row[key]
            end
        end
        tuples[#tuples + 1] = "(" .. table.concat(placeholders, ", ") .. ")"
    end
    return "INSERT INTO " .. self.table_name .. " (" .. table.concat(columns, ", ") .. ") VALUES "
        .. table.concat(tuples, ", "), bindings
end

function QueryBuilder:to_update(values)
    self:_require_table()
    if #self.conditions == 0 then error("update requires at least one where condition", 2) end
    if type(values) ~= "table" or next(values) == nil then error("update requires values", 2) end
    local sets, bindings = {}, {}
    for _, key in ipairs(sorted_keys(values)) do
        sets[#sets + 1] = identifier(key) .. " = ?"
        bindings[#bindings + 1] = values[key]
    end
    local where_sql, where_bindings = self:_where_sql()
    append(bindings, where_bindings)
    return "UPDATE " .. self.table_name .. " SET " .. table.concat(sets, ", ") .. " WHERE " .. where_sql, bindings
end

function QueryBuilder:to_delete()
    self:_require_table()
    if #self.conditions == 0 then error("delete requires at least one where condition", 2) end
    local where_sql, bindings = self:_where_sql()
    return "DELETE FROM " .. self.table_name .. " WHERE " .. where_sql, bindings
end

-- Explicit adapter > builder adapter > Database.default().
function QueryBuilder:_adapter(adapter)
    adapter = adapter or self.adapter
    if adapter ~= nil then
        if not is_adapter(adapter) then error("query builder requires a database adapter", 3) end
        return adapter
    end
    return require("crescent.database").default()
end

function QueryBuilder:get(adapter)
    local sql, bindings = self:to_sql()
    return self:_adapter(adapter):query(sql, bindings)
end

QueryBuilder.fetch = QueryBuilder.get

function QueryBuilder:first(adapter)
    local sql, bindings = self:_select_sql({ limit = 1 })
    local rows, err, errno, sqlstate, kind = self:_adapter(adapter):query(sql, bindings)
    if not rows then return nil, err, errno, sqlstate, kind end
    return rows[1]
end

function QueryBuilder:count(adapter)
    local sql, bindings = self:to_count_sql()
    local rows, err, errno, sqlstate, kind = self:_adapter(adapter):query(sql, bindings)
    if not rows then return nil, err, errno, sqlstate, kind end
    return tonumber(rows[1] and rows[1].aggregate) or 0
end

function QueryBuilder:exists(adapter)
    local count, err, errno, sqlstate, kind = self:count(adapter)
    if count == nil then return nil, err, errno, sqlstate, kind end
    return count > 0
end

-- Runs the SELECT through adapter:execute (kept for compatibility).
function QueryBuilder:execute(adapter)
    local sql, bindings = self:to_sql()
    return self:_adapter(adapter):execute(sql, bindings)
end

-- insert(values) or insert(adapter, values); same for update.
function QueryBuilder:insert(adapter, values)
    if values == nil and not is_adapter(adapter) then adapter, values = nil, adapter end
    local sql, bindings = self:to_insert(values)
    return self:_adapter(adapter):execute(sql, bindings)
end

function QueryBuilder:update(adapter, values)
    if values == nil and not is_adapter(adapter) then adapter, values = nil, adapter end
    local sql, bindings = self:to_update(values)
    return self:_adapter(adapter):execute(sql, bindings)
end

function QueryBuilder:delete(adapter)
    local sql, bindings = self:to_delete()
    return self:_adapter(adapter):execute(sql, bindings)
end

-- QueryBuilder.raw(sql, bindings[, adapter])
function QueryBuilder.raw(sql, bindings, adapter)
    if type(sql) ~= "string" then error("raw requires SQL", 2) end
    adapter = adapter or require("crescent.database").default()
    return adapter:query(sql, bindings or {})
end

local CAMEL_ALIASES = {
    orWhere = "or_where",
    whereNull = "where_null",
    orWhereNull = "or_where_null",
    whereNotNull = "where_not_null",
    orWhereNotNull = "or_where_not_null",
    whereIn = "where_in",
    orWhereIn = "or_where_in",
    whereNotIn = "where_not_in",
    whereRaw = "where_raw",
    orWhereRaw = "or_where_raw",
    leftJoin = "left_join",
    rightJoin = "right_join",
    orderBy = "order_by",
    toSql = "to_sql",
}

for alias, name in pairs(CAMEL_ALIASES) do
    QueryBuilder[alias] = function(self, ...) return self[name](self, ...) end
end

QueryBuilder.CAMEL_ALIASES = CAMEL_ALIASES
QueryBuilder.NULL = Sql.NULL

return QueryBuilder
