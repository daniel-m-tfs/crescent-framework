local MigrationRunner = {}
MigrationRunner.__index = MigrationRunner

local function sort_migrations(migrations)
    local result = {}
    for _, migration in ipairs(migrations or {}) do
        if type(migration) ~= "table" or type(migration.name) ~= "string" then
            error("migration requires a name", 3)
        end
        if type(migration.up) ~= "function" or type(migration.down) ~= "function" then
            error("migration " .. migration.name .. " requires up() and down()", 3)
        end
        result[#result + 1] = migration
    end
    table.sort(result, function(left, right) return left.name < right.name end)
    return result
end

local function execute(adapter, operation)
    if type(operation) == "string" then return adapter:execute(operation, {}) end
    if type(operation) == "table" and type(operation.sql) == "string" then
        return adapter:execute(operation.sql, operation.bindings or {})
    end
    return nil, "migration must return SQL or { sql, bindings }"
end

function MigrationRunner.new(adapter, applied)
    if type(adapter) ~= "table" or type(adapter.execute) ~= "function" then
        error("migration runner requires a database adapter", 2)
    end
    return setmetatable({ adapter = adapter, applied = applied or {} }, MigrationRunner)
end

function MigrationRunner:migrate(migrations)
    local applied_now = {}
    for _, migration in ipairs(sort_migrations(migrations)) do
        if not self.applied[migration.name] then
            local ok, operation = pcall(migration.up, migration)
            if not ok then return nil, migration.name, operation end
            local executed, execute_error = execute(self.adapter, operation)
            if not executed then return nil, migration.name, execute_error end
            self.applied[migration.name] = true
            self.applied[#self.applied + 1] = migration.name
            applied_now[#applied_now + 1] = migration.name
        end
    end
    return applied_now
end

function MigrationRunner:rollback(migrations)
    local by_name = {}
    for _, migration in ipairs(sort_migrations(migrations)) do by_name[migration.name] = migration end
    local rolled_back = {}
    for index = #self.applied, 1, -1 do
        local name = self.applied[index]
        local migration = by_name[name]
        if migration then
            local ok, operation = pcall(migration.down, migration)
            if not ok then return nil, name, operation end
            local executed, execute_error = execute(self.adapter, operation)
            if not executed then return nil, name, execute_error end
            table.remove(self.applied, index)
            self.applied[name] = nil
            rolled_back[#rolled_back + 1] = name
            break
        end
    end
    return rolled_back
end

return MigrationRunner