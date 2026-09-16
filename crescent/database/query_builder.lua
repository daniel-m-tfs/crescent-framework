-- crescent/database/query_builder.lua
-- Query Builder simples inspirado no Laravel/Eloquent
--
-- PROTEÇÃO SQL INJECTION:
-- - Valores: Escapados automaticamente via _escapeValue() 
-- - Identificadores (tabelas/colunas): Validados via _validateIdentifier()
-- - IMPORTANTE: Para queries raw, SEMPRE use bindings com placeholders (?)
--
-- EXEMPLOS DE USO:
--
-- 1. QueryBuilder básico:
--    local QB = require("crescent.database.query_builder")
--    local users = QB.table("users"):where("age", ">", 18):get()
--
-- 2. Query raw COM BINDINGS (SEGURO):
--    local results = QB.raw("SELECT * FROM users WHERE name = ? AND age > ?", {"Sara", 18})
--
-- 3. Query raw SEM bindings (EVITE - só use para queries fixas):
--    local results = QB.raw("SELECT COUNT(*) as total FROM users")
--
-- 4. Através do Model:
--    local User = require("src.users.models.users")
--    local users = User:query():where("status", "active"):orderBy("name"):get()
--    local custom = User:raw("SELECT * FROM users WHERE name LIKE ?", {"%Sara%"})

local sql_escape = require("crescent.database.sql_escape")

local QueryBuilder = {}
QueryBuilder.__index = QueryBuilder

local ALLOWED_OPERATORS = {
    ["="] = true, ["!="] = true, ["<>"] = true,
    ["<"] = true, ["<="] = true, [">"] = true, [">="] = true,
    ["LIKE"] = true, ["NOT LIKE"] = true,
}

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
    self._table = self:_escapeIdentifier(self:_validateIdentifier(table_name))
    return self
end

-- SELECT
function QueryBuilder:select(...)
    local columns = {...}
    if #columns == 0 then
        error("select requires at least one column")
    end
    self._selects = {}
    for _, column in ipairs(columns) do
        if column == "*" then
            table.insert(self._selects, column)
        else
            table.insert(self._selects, self:_escapeIdentifier(column))
        end
    end
    return self
end

-- WHERE
function QueryBuilder:where(column, operator, value)
    -- where(column, value) ou where(column, operator, value)
    if value == nil then
        value = operator
        operator = "="
    end

    if value == nil then
        return self:whereNull(column)
    end

    operator = self:_validateOperator(operator)
    
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

    if value == nil then
        table.insert(self._wheres, {
            column = column,
            operator = "IS NULL",
            value = nil,
            type = "OR"
        })
        return self
    end

    operator = self:_validateOperator(operator)
    
    table.insert(self._wheres, {
        column = column,
        operator = operator,
        value = value,
        type = "OR"
    })
    return self
end

function QueryBuilder:whereIn(column, values)
    if type(values) ~= "table" then
        error("whereIn values must be a table")
    end
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

    operator = self:_validateOperator(operator)
    
    table.insert(self._joins, {
        type = "INNER",
        table = self:_escapeIdentifier(table_name),
        first = self:_escapeIdentifier(first),
        operator = operator,
        second = self:_escapeIdentifier(second)
    })
    return self
end

function QueryBuilder:leftJoin(table_name, first, operator, second)
    if not second then
        second = operator
        operator = "="
    end

    operator = self:_validateOperator(operator)
    
    table.insert(self._joins, {
        type = "LEFT",
        table = self:_escapeIdentifier(table_name),
        first = self:_escapeIdentifier(first),
        operator = operator,
        second = self:_escapeIdentifier(second)
    })
    return self
end

-- ORDER BY
function QueryBuilder:orderBy(column, direction)
    direction = direction or "ASC"
    direction = type(direction) == "string" and string.upper(direction) or "ASC"
    if direction ~= "ASC" and direction ~= "DESC" then
        direction = "ASC"
    end
    table.insert(self._orderBy, {
        column = column,
        direction = direction
    })
    return self
end

-- LIMIT / OFFSET
function QueryBuilder:limit(num)
    if type(num) ~= "number" or num < 0 or num % 1 ~= 0 then
        error("LIMIT must be a non-negative integer")
    end
    self._limit = num
    return self
end

function QueryBuilder:offset(num)
    if type(num) ~= "number" or num < 0 or num % 1 ~= 0 then
        error("OFFSET must be a non-negative integer")
    end
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

    if type(page) ~= "number" or page < 1 or page % 1 ~= 0 then
        error("Page must be a positive integer")
    end
    if type(per_page) ~= "number" or per_page < 1 or per_page % 1 ~= 0 then
        error("Per-page must be a positive integer")
    end
    
    self:limit(per_page)
    self:offset((page - 1) * per_page)
    
    return self
end

-- Constrói só a cláusula WHERE (com o "WHERE " na frente), a partir de
-- self._wheres diretamente — usado tanto por toSql() quanto por update()/
-- delete(), que precisam do WHERE sem o resto do SELECT. Nunca extrai isso
-- via regex sobre SQL final (um valor contendo "ORDER BY"/"LIMIT" corromperia
-- a extração).
function QueryBuilder:_buildWhereClause()
    if #self._wheres == 0 then
        return ""
    end

    local where_clauses = {}
    for i, where in ipairs(self._wheres) do
        local clause

        if where.operator == "IN" then
            if #where.value == 0 then
                -- IN () é erro de sintaxe no MySQL; uma lista vazia nunca
                -- deve casar nada, então usa uma condição sempre falsa.
                clause = "1 = 0"
            else
                local values = {}
                for _, v in ipairs(where.value) do
                    table.insert(values, self:_escapeValue(v))
                end
                clause = string.format("%s IN (%s)", self:_escapeIdentifier(where.column), table.concat(values, ", "))
            end
        elseif where.operator == "IS NULL" or where.operator == "IS NOT NULL" then
            clause = string.format("%s %s", self:_escapeIdentifier(where.column), where.operator)
        else
            clause = string.format("%s %s %s",
                self:_escapeIdentifier(where.column), where.operator, self:_escapeValue(where.value))
        end

        if i == 1 then
            table.insert(where_clauses, "WHERE " .. clause)
        else
            table.insert(where_clauses, where.type .. " " .. clause)
        end
    end
    return table.concat(where_clauses, " ")
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
    local where_clause = self:_buildWhereClause()
    if where_clause ~= "" then
        sql = sql .. " " .. where_clause
    end

    -- ORDER BY
    if #self._orderBy > 0 then
        local orders = {}
        for _, order in ipairs(self._orderBy) do
            local direction = (order.direction == "DESC") and "DESC" or "ASC"
            table.insert(orders, self:_escapeIdentifier(order.column) .. " " .. direction)
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

-- Escape de valores (proteção SQL Injection)
function QueryBuilder:_escapeValue(value)
    return sql_escape.escape_value(value)
end

-- Escape de identificadores (nomes de colunas/tabelas) com backticks
function QueryBuilder:_escapeIdentifier(identifier)
    return sql_escape.escape_identifier(identifier)
end

function QueryBuilder:_validateOperator(operator)
    if type(operator) ~= "string" then
        error("Invalid SQL operator: " .. tostring(operator))
    end
    operator = string.upper(operator)
    if not ALLOWED_OPERATORS[operator] then
        error("Invalid SQL operator: " .. operator)
    end
    return operator
end

-- Valida nome de tabela/coluna (previne SQL Injection em identificadores)
function QueryBuilder:_validateIdentifier(identifier)
    -- Permite apenas letras, números, underscore e ponto
    if type(identifier) ~= "string" or not identifier:match("^[a-zA-Z0-9_.]+$") then
        error("Invalid identifier: " .. tostring(identifier) .. " (only alphanumeric, underscore and dot allowed)")
    end
    return identifier
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
    
    -- Sem driver instalado: NÃO finge sucesso (ver comentário em update()).
    print("⚠️  [SEM DRIVER] Nada foi executado. SQL que seria rodado:", sql)
    return nil, "Driver MySQL não instalado. Execute: luarocks install luasql-mysql"
end

function QueryBuilder:first()
    self:limit(1)
    local results, err = self:get()
    
    if not results then return nil, err end
    if type(results) == "table" and #results > 0 then
        return results[1]
    end
    return nil
end

function QueryBuilder:count()
    -- Não muta self._selects permanentemente: count() precisa poder ser
    -- chamado numa instância que ainda vai ser reusada (API é fluente/
    -- encadeável, e mutar _selects aqui faria qualquer .get() seguinte
    -- também virar COUNT(*)).
    local original_selects = self._selects
    self._selects = {"COUNT(*) as count"}
    local results, err = self:get()
    self._selects = original_selects

    if err or not results or not results[1] then
        return 0, err
    end
    return tonumber(results[1].count) or 0
end

-- INSERT
function QueryBuilder:insert(data)
    local columns = {}
    local values = {}
    
    for k, v in pairs(data) do
        table.insert(columns, self:_escapeIdentifier(k))
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
    
    -- Sem driver instalado: NÃO finge sucesso (ver comentário em update()).
    -- Retornar um ID fake (ex: 1) faria Model:create() achar que inseriu de
    -- verdade quando nada foi persistido — perda de dados silenciosa.
    print("⚠️  [SEM DRIVER] Nada foi inserido. SQL que seria rodado:", sql)
    return nil, "Driver MySQL não instalado. Execute: luarocks install luasql-mysql"
end

-- UPDATE
function QueryBuilder:update(data)
    local sets = {}
    
    for k, v in pairs(data) do
        table.insert(sets, string.format("%s = %s", self:_escapeIdentifier(k), self:_escapeValue(v)))
    end
    
    local sql = string.format("UPDATE %s SET %s", self._table, table.concat(sets, ", "))

    local where_clause = self:_buildWhereClause()
    if where_clause ~= "" then
        sql = sql .. " " .. where_clause
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

    -- Sem driver instalado: NÃO finge sucesso. Um retorno com a mesma forma
    -- de sucesso (affected=1) faria o caller (ex: Model:update()) achar que
    -- persistiu quando na verdade nada foi escrito no banco.
    print("⚠️  [SEM DRIVER] Nada foi executado. SQL que seria rodado:", sql)
    return nil, "Driver MySQL não instalado. Execute: luarocks install luasql-mysql"
end

-- DELETE
function QueryBuilder:delete()
    local sql = "DELETE FROM " .. self._table

    local where_clause = self:_buildWhereClause()
    if where_clause ~= "" then
        sql = sql .. " " .. where_clause
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

    -- Sem driver instalado: NÃO finge sucesso (ver comentário em update()).
    print("⚠️  [SEM DRIVER] Nada foi executado. SQL que seria rodado:", sql)
    return nil, "Driver MySQL não instalado. Execute: luarocks install luasql-mysql"
end

-- Funções estáticas de conveniência
local M = {}

function M.table(table_name)
    return QueryBuilder.new():table(table_name)
end

-- Executa query SQL raw (com prepared statements quando possível)
function M.raw(sql, bindings)
    bindings = bindings or {}
    
    -- Se MySQL disponível E driver instalado, executa query real
    if mysql_available and mysql_driver_available and MySQL then
        local results, err = MySQL:query(sql, bindings)
        if err then
            print("❌ Erro MySQL (raw):", err)
            return nil, err
        end
        return results
    end
    
    -- Sem driver instalado: NÃO finge sucesso (ver comentário em update()).
    print("⚠️  [SEM DRIVER] Nada foi executado. SQL que seria rodado (raw):", sql)
    return nil, "Driver MySQL não instalado. Execute: luarocks install luasql-mysql"
end

-- Alias para raw (convenção)
function M.query(sql, bindings)
    return M.raw(sql, bindings)
end

return M
