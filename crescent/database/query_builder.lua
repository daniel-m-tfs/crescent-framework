-- crescent/database/query_builder.lua
-- Query Builder simples inspirado no Laravel/Eloquent

local QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

-- MySQL Connection (opcional)
local MySQL = nil
local mysql_available = false
local mysql_driver_available = false

local ok = pcall(function()
    MySQL = require("crescent.database.mysql")
    mysql_available = true
    -- Verifica se o driver está realmente disponível
    mysql_driver_available = MySQL.isDriverAvailable and MySQL.isDriverAvailable() or false
end)

-- Cria nova instância
function QueryBuilder.new()
    local self = setmetatable({}, QueryBuilder)
    self._table = nil
    self._wheres = {}
    self._selects = {"*"}
    self._joins = {}
    self._orderBy = {}
    self._limit = nil
    self._offset = nil
    return self
end

-- Define tabela
function QueryBuilder:table(table_name)
    self._table = table_name
    return self
end

-- SELECT
function QueryBuilder:select(...)
    self._selects = {...}
    return self
end

-- WHERE
function QueryBuilder:where(column, operator, value)
    -- where(column, value) ou where(column, operator, value)
    if value == nil then
        value = operator
        operator = "="
    end
    
    table.insert(self._wheres, {
        column = column,
        operator = operator,
        value = value,
        type = "AND"
    })
    return self
end

function QueryBuilder:orWhere(column, operator, value)
    if value == nil then
        value = operator
        operator = "="
    end
    
    table.insert(self._wheres, {
        column = column,
        operator = operator,
        value = value,
        type = "OR"
    })
    return self
end

function QueryBuilder:whereIn(column, values)
    table.insert(self._wheres, {
        column = column,
        operator = "IN",
        value = values,
        type = "AND"
    })
    return self
end

function QueryBuilder:whereNull(column)
    table.insert(self._wheres, {
        column = column,
        operator = "IS NULL",
        value = nil,
        type = "AND"
    })
    return self
end

function QueryBuilder:whereNotNull(column)
    table.insert(self._wheres, {
        column = column,
        operator = "IS NOT NULL",
        value = nil,
        type = "AND"
    })
    return self
end

-- JOIN
function QueryBuilder:join(table_name, first, operator, second)
    if not second then
        second = operator
        operator = "="
    end
    
    table.insert(self._joins, {
        type = "INNER",
        table = table_name,
        first = first,
        operator = operator,
        second = second
    })
    return self
end

function QueryBuilder:leftJoin(table_name, first, operator, second)
    if not second then
        second = operator
        operator = "="
    end
    
    table.insert(self._joins, {
        type = "LEFT",
        table = table_name,
        first = first,
        operator = operator,
        second = second
    })
    return self
end

-- ORDER BY
function QueryBuilder:orderBy(column, direction)
    direction = direction or "ASC"
    table.insert(self._orderBy, {
        column = column,
        direction = direction
    })
    return self
end

-- LIMIT / OFFSET
function QueryBuilder:limit(num)
    self._limit = num
    return self
end

function QueryBuilder:offset(num)
    self._offset = num
    return self
end

function QueryBuilder:skip(num)
    return self:offset(num)
end

function QueryBuilder:take(num)
    return self:limit(num)
end

-- Helpers de paginação
function QueryBuilder:paginate(page, per_page)
    page = page or 1
    per_page = per_page or 15
    
    self:limit(per_page)
    self:offset((page - 1) * per_page)
    
    return self
end

-- Constrói SQL
function QueryBuilder:toSql()
    local sql = "SELECT " .. table.concat(self._selects, ", ")
    sql = sql .. " FROM " .. self._table
    
    -- JOINs
    for _, join in ipairs(self._joins) do
        sql = sql .. string.format(" %s JOIN %s ON %s %s %s",
            join.type, join.table, join.first, join.operator, join.second)
    end
    
    -- WHEREs
    if #self._wheres > 0 then
        local where_clauses = {}
        for i, where in ipairs(self._wheres) do
            local clause
            
            if where.operator == "IN" then
                local values = {}
                for _, v in ipairs(where.value) do
                    table.insert(values, self:_escapeValue(v))
                end
                clause = string.format("%s IN (%s)", where.column, table.concat(values, ", "))
            elseif where.operator == "IS NULL" or where.operator == "IS NOT NULL" then
                clause = string.format("%s %s", where.column, where.operator)
            else
                clause = string.format("%s %s %s", 
                    where.column, where.operator, self:_escapeValue(where.value))
            end
            
            if i == 1 then
                table.insert(where_clauses, "WHERE " .. clause)
            else
                table.insert(where_clauses, where.type .. " " .. clause)
            end
        end
        sql = sql .. " " .. table.concat(where_clauses, " ")
    end
    
    -- ORDER BY
    if #self._orderBy > 0 then
        local orders = {}
        for _, order in ipairs(self._orderBy) do
            table.insert(orders, order.column .. " " .. order.direction)
        end
        sql = sql .. " ORDER BY " .. table.concat(orders, ", ")
    end
    
    -- LIMIT
    if self._limit then
        sql = sql .. " LIMIT " .. self._limit
    end
    
    -- OFFSET
    if self._offset then
        sql = sql .. " OFFSET " .. self._offset
    end
    
    return sql
end

-- Escape de valores (básico)
function QueryBuilder:_escapeValue(value)
    if type(value) == "string" then
        return "'" .. value:gsub("'", "''") .. "'"
    elseif type(value) == "number" then
        return tostring(value)
    elseif type(value) == "boolean" then
        return value and "1" or "0"
    elseif value == nil then
        return "NULL"
    else
        return "'" .. tostring(value) .. "'"
    end
end

-- Execução
function QueryBuilder:get()
    local sql = self:toSql()
    
    -- Se MySQL disponível E driver instalado, executa query real
    if mysql_available and mysql_driver_available and MySQL then
        local results, err = MySQL:query(sql)
        if err then
            print("❌ Erro MySQL:", err)
            return nil, err
        end
        return results
    end
    
    -- Fallback: modo mock
    print("⚠️  [MOCK] SQL:", sql)
    return {
        note = "Mock result - instale luasql-mysql para queries reais"
    }
end

function QueryBuilder:first()
    self:limit(1)
    local results = self:get()
    
    if not results then return nil end
    if type(results) == "table" and #results > 0 then
        return results[1]
    end
    return nil
end

function QueryBuilder:count()
    self._selects = {"COUNT(*) as count"}
    local results = self:get()
    return results[1] and results[1].count or 0
end

-- INSERT
function QueryBuilder:insert(data)
    local columns = {}
    local values = {}
    
    for k, v in pairs(data) do
        table.insert(columns, k)
        table.insert(values, self:_escapeValue(v))
    end
    
    local sql = string.format("INSERT INTO %s (%s) VALUES (%s)",
        self._table,
        table.concat(columns, ", "),
        table.concat(values, ", ")
    )
    
    -- Se MySQL disponível E driver instalado, executa e retorna ID
    if mysql_available and mysql_driver_available and MySQL then
        local id, err = MySQL:insert(sql)
        if err then
            print("❌ Erro MySQL:", err)
            return nil, err
        end
        return id
    end
    
    -- Fallback: modo mock (retorna ID diretamente)
    print("⚠️  [MOCK] SQL:", sql)
    return 1  -- Retorna apenas o ID no modo mock
end

-- UPDATE
function QueryBuilder:update(data)
    local sets = {}
    
    for k, v in pairs(data) do
        table.insert(sets, string.format("%s = %s", k, self:_escapeValue(v)))
    end
    
    local sql = string.format("UPDATE %s SET %s", self._table, table.concat(sets, ", "))
    
    if #self._wheres > 0 then
        -- Adiciona WHERE (reutiliza lógica do toSql)
        local temp_sql = self:toSql()
        local where_part = temp_sql:match("WHERE.+")
        if where_part then
            where_part = where_part:gsub("ORDER BY.+", ""):gsub("LIMIT.+", "")
            sql = sql .. " " .. where_part
        end
    end
    
    -- Se MySQL disponível E driver instalado, executa
    if mysql_available and mysql_driver_available and MySQL then
        local result, err = MySQL:update(sql)
        if err then
            print("❌ Erro MySQL:", err)
            return nil, err
        end
        return result
    end
    
    -- Fallback: modo mock
    print("⚠️  [MOCK] SQL:", sql)
    return {
        affected = 1,
        note = "Mock result - instale luasql-mysql"
    }
end

-- DELETE
function QueryBuilder:delete()
    local sql = "DELETE FROM " .. self._table
    
    if #self._wheres > 0 then
        local temp_sql = self:toSql()
        local where_part = temp_sql:match("WHERE.+")
        if where_part then
            where_part = where_part:gsub("ORDER BY.+", ""):gsub("LIMIT.+", "")
            sql = sql .. " " .. where_part
        end
    end
    
    -- Se MySQL disponível E driver instalado, executa
    if mysql_available and mysql_driver_available and MySQL then
        local result, err = MySQL:delete(sql)
        if err then
            print("❌ Erro MySQL:", err)
            return nil, err
        end
        return result
    end
    
    -- Fallback: modo mock
    print("⚠️  [MOCK] SQL:", sql)
    return {
        affected = 1,
        note = "Mock result - instale luasql-mysql"
    }
end

-- Funções estáticas de conveniência
local M = {}

function M.table(table_name)
    return QueryBuilder.new():table(table_name)
end

function M.raw(sql)
    print("📊 SQL (raw):", sql)
    return {
        sql = sql,
        note = "Raw query - mock result"
    }
end

return M
