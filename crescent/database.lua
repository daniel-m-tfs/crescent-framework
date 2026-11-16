-- Process-wide database manager. Configure once at boot with
-- `Database.configure(config.database)`; models and the query builder use
-- `Database.default()` whenever no adapter is passed explicitly.
local Sql = require("crescent.database.sql")

local Database = {}

Database.NULL = Sql.NULL

local DRIVERS = {
    mysql = "crescent.database.mysql",
}

local current

local function assert_adapter(adapter)
    if type(adapter) ~= "table" or type(adapter.query) ~= "function" or type(adapter.execute) ~= "function" then
        error("database adapter must implement query() and execute()", 3)
    end
    return adapter
end

-- cfg: config.database (driver defaults to "mysql"). options.driver injects
-- a fake `resty.mysql` module or factory, mostly for tests.
function Database.configure(cfg, options)
    if type(cfg) ~= "table" then error("database configuration must be a table", 2) end
    options = options or {}
    local driver_name = cfg.driver or "mysql"
    local module_name = DRIVERS[driver_name]
    if not module_name then error("unsupported database driver: " .. tostring(driver_name), 2) end
    current = require(module_name).new(cfg, options.driver)
    return current
end

function Database.set_default(adapter)
    current = assert_adapter(adapter)
    return current
end

function Database.reset()
    current = nil
end

function Database.is_configured()
    return current ~= nil
end

function Database.default()
    if not current then
        error("database is not configured; call Database.configure(config.database) at boot", 2)
    end
    return current
end

-- Returns `adapter` when given, otherwise the default adapter (or nil when
-- `optional` and nothing is configured).
function Database.resolve(adapter, optional)
    if adapter ~= nil then return assert_adapter(adapter) end
    if optional and not current then return nil end
    return Database.default()
end

function Database.query(sql, bindings)
    return Database.default():query(sql, bindings)
end

function Database.execute(sql, bindings)
    return Database.default():execute(sql, bindings)
end

function Database.raw(sql, bindings)
    return Database.default():query(sql, bindings)
end

function Database.transaction(fn)
    return Database.default():transaction(fn)
end

function Database.table(name, adapter)
    return require("crescent.database.query_builder").new(adapter):table(name)
end

return Database
