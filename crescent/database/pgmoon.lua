local PgmoonAdapter = {}
PgmoonAdapter.__index = PgmoonAdapter

local unpack_values = table.unpack or unpack

local function default_factory(config)
    local pgmoon = require("pgmoon")
    return pgmoon.new(config)
end

local function bindings_call(connection, sql, bindings)
    bindings = bindings or {}
    if type(bindings) ~= "table" then error("database bindings must be a table", 3) end
    return connection:query(sql, unpack_values(bindings))
end

function PgmoonAdapter.new(config, factory)
    config = config or {}
    return setmetatable({
        config = config,
        factory = factory or default_factory,
        connection = nil,
    }, PgmoonAdapter)
end

function PgmoonAdapter:connect()
    if self.connection then return true end
    self.connection = self.factory(self.config)
    local ok, err = self.connection:connect()
    if not ok then
        self.connection = nil
        return nil, err
    end
    return true
end

function PgmoonAdapter:query(sql, bindings)
    local ok, err = self:connect()
    if not ok then return nil, err end
    return bindings_call(self.connection, sql, bindings)
end

function PgmoonAdapter:execute(sql, bindings)
    return self:query(sql, bindings)
end

function PgmoonAdapter:transaction(operations)
    if type(operations) ~= "table" then return nil, "transaction operations must be a table" end
    local ok, err = self:connect()
    if not ok then return nil, err end
    local started, start_error = self.connection:query("BEGIN")
    if not started then return nil, start_error end

    for _, operation in ipairs(operations) do
        if type(operation) ~= "table" or type(operation.sql) ~= "string" then
            self.connection:query("ROLLBACK")
            return nil, "invalid transaction operation"
        end
        local result, operation_error = bindings_call(self.connection, operation.sql, operation.bindings)
        if not result then
            self.connection:query("ROLLBACK")
            return nil, operation_error
        end
    end

    local committed, commit_error = self.connection:query("COMMIT")
    if not committed then
        self.connection:query("ROLLBACK")
        return nil, commit_error
    end
    return true
end

function PgmoonAdapter:close()
    if not self.connection then return true end
    local result, err = self.connection:disconnect()
    self.connection = nil
    return result, err
end

return PgmoonAdapter