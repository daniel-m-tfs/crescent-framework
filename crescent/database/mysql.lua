-- MySQL adapter on lua-resty-mysql (non-blocking cosockets).
--
-- Every query borrows a connection from the nginx cosocket pool and gives it
-- back with set_keepalive(); a cosocket can never be shared between requests,
-- so the adapter itself holds no connection and can be a module-level value.
-- lua-resty-mysql speaks the text protocol: `?` placeholders are bound by
-- crescent.database.sql with ngx.quote_sql_str.
local Sql = require("crescent.database.sql")

local MySQL = {}
MySQL.__index = MySQL

local Connection = {}
Connection.__index = Connection

local Transaction = {}
Transaction.__index = Transaction

local SERVER_STATUS_IN_TRANS = 1

local ERROR_KINDS = {
    [1062] = "unique_violation",
    [1586] = "unique_violation",
    [1451] = "foreign_key_violation",
    [1452] = "foreign_key_violation",
    [1048] = "not_null_violation",
    [1213] = "deadlock",
    [1205] = "lock_timeout",
}

local DEFAULTS = {
    host = "127.0.0.1",
    port = 3306,
    charset = "utf8mb4",
    connect_timeout = 5000,
    timeout = 10000,
    max_idle_timeout = 10000,
    pool_size = 100,
    max_packet_size = 1024 * 1024,
    keepalive = true,
}

-- Symbolic error kind for a MySQL errno ("unique_violation", ...).
function MySQL.error_kind(errno)
    return ERROR_KINDS[tonumber(errno)]
end

function MySQL.is_unique_violation(errno, kind)
    return kind == "unique_violation" or ERROR_KINDS[tonumber(errno)] == "unique_violation"
end

local function default_factory()
    return require("resty.mysql")
end

local function has_bit(value, flag)
    return type(value) == "number" and math.floor(value / flag) % 2 == 1
end

local function normalize_rows(rows)
    local null = Sql.NULL
    for _, row in ipairs(rows) do
        for key, value in pairs(row) do
            if value == null then row[key] = nil end
        end
    end
    return rows
end

-- SELECT -> array of rows; writes -> { affected_rows, insert_id }.
local function normalize(result)
    if type(result) ~= "table" then return result end
    if result.affected_rows ~= nil or result.insert_id ~= nil or result.server_status ~= nil then
        return {
            affected_rows = result.affected_rows or 0,
            insert_id = result.insert_id or 0,
            warning_count = result.warning_count,
            message = result.message,
        }
    end
    return normalize_rows(result)
end

function MySQL.new(config, driver)
    config = config or {}
    if type(config) ~= "table" then error("mysql config must be a table", 2) end
    local settings = {}
    for key, value in pairs(DEFAULTS) do settings[key] = value end
    for key, value in pairs(config) do settings[key] = value end
    if not settings.path and (type(settings.host) ~= "string" or settings.host == "") then
        error("mysql config requires host", 2)
    end
    if type(settings.database) ~= "string" or settings.database == "" then
        error("mysql config requires database", 2)
    end
    if type(settings.user) ~= "string" or settings.user == "" then
        error("mysql config requires user", 2)
    end

    local factory = driver or default_factory
    if type(factory) == "table" then
        local module = factory
        factory = function() return module end
    end
    if type(factory) ~= "function" then error("mysql driver must be a module or factory function", 2) end
    return setmetatable({ config = settings, factory = factory }, MySQL)
end

function MySQL:is_adapter()
    return true
end

-- Opens (or reuses from the pool) one connection and returns it pinned to the
-- caller. The caller must call :release() (pool) or :close() on it.
function MySQL:connect()
    local config = self.config
    local driver = self.factory()
    local raw, err = driver.new()
    if not raw then return nil, "mysql: unable to create connection: " .. tostring(err), nil, nil, "connection" end
    if raw.set_timeout then raw:set_timeout(config.connect_timeout) end

    local ok, connect_err, errno, sqlstate = raw:connect({
        host = config.host,
        port = config.port,
        path = config.path,
        database = config.database,
        user = config.user,
        password = config.password or "",
        charset = config.charset,
        max_packet_size = config.max_packet_size,
        pool = config.pool_name,
        ssl = config.ssl,
        ssl_verify = config.ssl_verify,
    })
    if not ok then
        if raw.close then pcall(raw.close, raw) end
        return nil, "mysql: connect failed: " .. tostring(connect_err), errno, sqlstate, "connection"
    end
    if raw.set_timeout then raw:set_timeout(config.timeout) end
    return setmetatable({ raw = raw, adapter = self, in_transaction = false, broken = false }, Connection)
end

function Connection:query(sql, bindings)
    if self.finished then return nil, "mysql: connection already released", nil, nil, "connection" end
    local bound, bind_err = Sql.bind(sql, bindings)
    if not bound then return nil, "mysql: " .. bind_err, nil, nil, "bind" end

    local result, err, errno, sqlstate = self.raw:query(bound)
    if not result then
        -- errno is only set for server errors; anything else (timeout, closed
        -- socket, protocol error) leaves the connection unusable.
        if errno == nil then self.broken = true end
        return nil, "mysql: " .. tostring(err), errno, sqlstate, MySQL.error_kind(errno) or (errno == nil and "connection" or "query")
    end
    -- Multi-statement results: keep the first one, drain the rest.
    while err == "again" do
        if not self.raw.read_result then self.broken = true break end
        local _, more_err, more_errno, more_sqlstate = self.raw:read_result()
        if more_err ~= "again" and more_err ~= nil then
            if more_errno == nil then self.broken = true end
            return nil, "mysql: " .. tostring(more_err), more_errno, more_sqlstate, MySQL.error_kind(more_errno) or "query"
        end
        err = more_err
    end
    if type(result) == "table" and result.server_status ~= nil then
        self.server_in_transaction = has_bit(result.server_status, SERVER_STATUS_IN_TRANS)
    end
    return normalize(result)
end

Connection.execute = Connection.query

-- Gives the connection back to the pool, or closes it when it cannot be
-- safely reused (broken, open transaction, keepalive disabled).
function Connection:release()
    if self.finished then return true end
    self.finished = true
    local config = self.adapter.config
    if self.broken or self.in_transaction or self.server_in_transaction or not config.keepalive then
        return self:_close()
    end
    local ok, err = self.raw:set_keepalive(config.max_idle_timeout, config.pool_size)
    if not ok then
        self:_close()
        return nil, err
    end
    return true
end

function Connection:_close()
    self.finished = true
    if self.raw.close then pcall(self.raw.close, self.raw) end
    return true
end

function Connection:close()
    if self.finished then return true end
    return self:_close()
end

-- One-shot query on a pooled connection.
function MySQL:query(sql, bindings)
    local conn, err, errno, sqlstate, kind = self:connect()
    if not conn then return nil, err, errno, sqlstate, kind end
    local result, query_err, query_errno, query_sqlstate, query_kind = conn:query(sql, bindings)
    conn:release()
    return result, query_err, query_errno, query_sqlstate, query_kind
end

MySQL.execute = MySQL.query

local function packed(...)
    return { n = select("#", ...), ... }
end

local unpack_values = table.unpack or unpack

-- A failed callback is one that raises, returns false, or returns nil, err.
local function callback_failed(results)
    if not results[1] then return true, results[2] end
    local first = results[2]
    if first == false then return true, results[3] or "transaction aborted" end
    if first == nil and results.n >= 3 and results[3] ~= nil then return true, results[3] end
    return false
end

local function transaction_results(results)
    if results.n <= 1 or results[2] == nil then return true end
    return unpack_values(results, 2, results.n)
end

local function new_transaction(conn)
    return setmetatable({ conn = conn, depth = 0, savepoints = 0 }, Transaction)
end

function Transaction:is_adapter()
    return true
end

function Transaction:query(sql, bindings)
    if self.done then return nil, "mysql: transaction already finished", nil, nil, "transaction" end
    return self.conn:query(sql, bindings)
end

Transaction.execute = Transaction.query

-- Nested transactions use savepoints on the same connection.
function Transaction:transaction(fn)
    if self.done then return nil, "mysql: transaction already finished", nil, nil, "transaction" end
    self.savepoints = self.savepoints + 1
    local name = "crescent_sp_" .. self.savepoints
    local ok, err, errno, sqlstate, kind = self.conn:query("SAVEPOINT " .. name)
    if not ok then return nil, err, errno, sqlstate, kind end
    local results = packed(pcall(fn, self))
    local failed, failure = callback_failed(results)
    if failed then
        local rolled_back, rollback_err = self.conn:query("ROLLBACK TO SAVEPOINT " .. name)
        if not rolled_back then return nil, rollback_err end
        return nil, failure
    end
    local released, release_err = self.conn:query("RELEASE SAVEPOINT " .. name)
    if not released then return nil, release_err end
    return transaction_results(results)
end

function Transaction:connect()
    return self.conn
end

function Transaction:close()
    return true
end

-- Runs fn(tx) on ONE pinned connection between START TRANSACTION and
-- COMMIT. Raising, returning false or returning nil, err rolls back.
-- A connection is only pooled again after a successful COMMIT/ROLLBACK.
function MySQL:transaction(fn)
    if type(fn) ~= "function" then return nil, "transaction requires a function" end
    local conn, err, errno, sqlstate, kind = self:connect()
    if not conn then return nil, err, errno, sqlstate, kind end

    local started, start_err, start_errno, start_sqlstate, start_kind = conn:query("START TRANSACTION")
    if not started then
        conn:close()
        return nil, start_err, start_errno, start_sqlstate, start_kind
    end
    conn.in_transaction = true
    local tx = new_transaction(conn)
    local results = packed(pcall(fn, tx))
    tx.done = true

    local failed, failure = callback_failed(results)
    if failed then
        local rolled_back = conn:query("ROLLBACK")
        if rolled_back then
            conn.in_transaction = false
            conn:release()
        else
            conn:close()
        end
        return nil, failure
    end

    local committed, commit_err, commit_errno, commit_sqlstate, commit_kind = conn:query("COMMIT")
    if not committed then
        pcall(conn.query, conn, "ROLLBACK")
        conn:close()
        return nil, commit_err, commit_errno, commit_sqlstate, commit_kind
    end
    conn.in_transaction = false
    conn:release()
    return transaction_results(results)
end

-- Connections are per query, so there is nothing to close at adapter level.
function MySQL:close()
    return true
end

MySQL.Connection = Connection
MySQL.Transaction = Transaction

return MySQL
