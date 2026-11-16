local QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

local OPERATORS = {
    ["="] = true, ["!="] = true, ["<>"] = true,
    ["<"] = true, ["<="] = true, [">"] = true, [">="] = true,
    ["LIKE"] = true, ["NOT LIKE"] = true,
}

local function identifier(value)
    if type(value) ~= "string" or value == "" then
        error("SQL identifier must be a non-empty string", 3)
    end
    local parts = {}
    for part in value:gmatch("[^%.]+") do
        if not part:match("^[%a_][%w_]*$") then
            error("invalid SQL identifier: " .. value, 3)
        end
        parts[#parts + 1] = "`" .. part .. "`"
    end
    if #parts == 0 then error("invalid SQL identifier: " .. value, 3) end
    return table.concat(parts, ".")
end

local function integer(value, name)
    if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
        error(name .. " must be a non-negative integer", 3)
    end
    return value
end

local function sorted_keys(values)
    local keys = {}
    for key in pairs(values) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function QueryBuilder.new()
    return setmetatable({
        table_name = nil,
        columns = { "*" },
        conditions = {},
        orders = {},
        limit_value = nil,
        offset_value = nil,
    }, QueryBuilder)
end

function QueryBuilder:table(value)
    self.table_name = identifier(value)
    return self
end

function QueryBuilder:from(value)
    return self:table(value)
end

function QueryBuilder:select(...)
    local values = { ... }
    if #values == 0 then error("select requires at least one column", 2) end
    self.columns = {}
    for _, value in ipairs(values) do
        self.columns[#self.columns + 1] = value == "*" and "*" or identifier(value)
    end
    return self
end

function QueryBuilder:where(column, operator, value)
    if value == nil then value, operator = operator, "=" end
    if value == nil then
        self.conditions[#self.conditions + 1] = { column = identifier(column), operator = "IS NULL" }
        return self
    end
    operator = type(operator) == "string" and operator:upper() or ""
    if not OPERATORS[operator] then error("invalid SQL operator: " .. tostring(operator), 2) end
    self.conditions[#self.conditions + 1] = {
        column = identifier(column), operator = operator, value = value,
    }
    return self
end

function QueryBuilder:where_in(column, values)
    if type(values) ~= "table" then error("where_in values must be a table", 2) end
    self.conditions[#self.conditions + 1] = {
        column = identifier(column), operator = "IN", values = values,
    }
    return self
end

function QueryBuilder:whereIn(column, values)
    return self:where_in(column, values)
end

function QueryBuilder:order_by(column, direction)
    direction = type(direction) == "string" and direction:upper() or "ASC"
    if direction ~= "ASC" and direction ~= "DESC" then
        error("order direction must be ASC or DESC", 2)
    end
    self.orders[#self.orders + 1] = identifier(column) .. " " .. direction
    return self
end

function QueryBuilder:orderBy(column, direction)
    return self:order_by(column, direction)
end

function QueryBuilder:limit(value)
    self.limit_value = integer(value, "limit")
    return self
end

function QueryBuilder:offset(value)
    self.offset_value = integer(value, "offset")
    return self
end

function QueryBuilder:to_sql()
    if not self.table_name then error("query requires a table", 2) end
    local sql = "SELECT " .. table.concat(self.columns, ", ") .. " FROM " .. self.table_name
    local bindings = {}
    local clauses = {}
    for _, condition in ipairs(self.conditions) do
        if condition.operator == "IS NULL" then
            clauses[#clauses + 1] = condition.column .. " IS NULL"
        elseif condition.operator == "IN" then
            if #condition.values == 0 then
                clauses[#clauses + 1] = "1 = 0"
            else
                local placeholders = {}
                for _, value in ipairs(condition.values) do
                    placeholders[#placeholders + 1] = "?"
                    bindings[#bindings + 1] = value
                end
                clauses[#clauses + 1] = condition.column .. " IN (" .. table.concat(placeholders, ", ") .. ")"
            end
        else
            clauses[#clauses + 1] = condition.column .. " " .. condition.operator .. " ?"
            bindings[#bindings + 1] = condition.value
        end
    end
    if #clauses > 0 then sql = sql .. " WHERE " .. table.concat(clauses, " AND ") end
    if #self.orders > 0 then sql = sql .. " ORDER BY " .. table.concat(self.orders, ", ") end
    if self.limit_value then sql = sql .. " LIMIT " .. self.limit_value end
    if self.offset_value then sql = sql .. " OFFSET " .. self.offset_value end
    return sql, bindings
end

function QueryBuilder:to_insert(values)
    if not self.table_name then error("query requires a table", 2) end
    if type(values) ~= "table" or next(values) == nil then error("insert requires values", 2) end
    local keys, placeholders, bindings = sorted_keys(values), {}, {}
    for _, key in ipairs(keys) do
        identifier(key)
        placeholders[#placeholders + 1] = "?"
        bindings[#bindings + 1] = values[key]
    end
    local columns = {}
    for _, key in ipairs(keys) do columns[#columns + 1] = identifier(key) end
    return "INSERT INTO " .. self.table_name .. " (" .. table.concat(columns, ", ") .. ") VALUES (" .. table.concat(placeholders, ", ") .. ")", bindings
end

function QueryBuilder:to_update(values)
    if not self.table_name then error("query requires a table", 2) end
    if #self.conditions == 0 then error("update requires at least one where condition", 2) end
    if type(values) ~= "table" or next(values) == nil then error("update requires values", 2) end
    local sets, bindings = {}, {}
    for _, key in ipairs(sorted_keys(values)) do
        sets[#sets + 1] = identifier(key) .. " = ?"
        bindings[#bindings + 1] = values[key]
    end
    local where_sql, where_bindings = self:_where_sql()
    for _, value in ipairs(where_bindings) do bindings[#bindings + 1] = value end
    return "UPDATE " .. self.table_name .. " SET " .. table.concat(sets, ", ") .. " WHERE " .. where_sql, bindings
end

function QueryBuilder:to_delete()
    if not self.table_name then error("query requires a table", 2) end
    if #self.conditions == 0 then error("delete requires at least one where condition", 2) end
    local where_sql, bindings = self:_where_sql()
    return "DELETE FROM " .. self.table_name .. " WHERE " .. where_sql, bindings
end

function QueryBuilder:_where_sql()
    local clauses, bindings = {}, {}
    for _, condition in ipairs(self.conditions) do
        if condition.operator == "IS NULL" then
            clauses[#clauses + 1] = condition.column .. " IS NULL"
        elseif condition.operator == "IN" then
            if #condition.values == 0 then
                clauses[#clauses + 1] = "1 = 0"
            else
                local placeholders = {}
                for _, value in ipairs(condition.values) do
                    placeholders[#placeholders + 1] = "?"
                    bindings[#bindings + 1] = value
                end
                clauses[#clauses + 1] = condition.column .. " IN (" .. table.concat(placeholders, ", ") .. ")"
            end
        else
            clauses[#clauses + 1] = condition.column .. " " .. condition.operator .. " ?"
            bindings[#bindings + 1] = condition.value
        end
    end
    return table.concat(clauses, " AND "), bindings
end

function QueryBuilder:toSql()
    return self:to_sql()
end

function QueryBuilder:fetch(adapter)
    if type(adapter) ~= "table" or type(adapter.query) ~= "function" then
        error("query builder requires a database adapter", 2)
    end
    local sql, bindings = self:to_sql()
    return adapter:query(sql, bindings)
end

function QueryBuilder:execute(adapter)
    if type(adapter) ~= "table" or type(adapter.execute) ~= "function" then
        error("query builder requires a database adapter", 2)
    end
    local sql, bindings = self:to_sql()
    return adapter:execute(sql, bindings)
end

function QueryBuilder:insert(adapter, values)
    local sql, bindings = self:to_insert(values)
    return adapter:execute(sql, bindings)
end

function QueryBuilder:update(adapter, values)
    local sql, bindings = self:to_update(values)
    return adapter:execute(sql, bindings)
end

function QueryBuilder:delete(adapter)
    local sql, bindings = self:to_delete()
    return adapter:execute(sql, bindings)
end

return QueryBuilder