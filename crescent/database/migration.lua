-- Migration runner with a persistent `migrations` table.
--
-- Files live in `migrations/*.lua` (sorted by name) and return
--   { up = function(db) return sql_or_list end, down = function(db) ... end }
-- where each statement is a SQL string or { sql = ..., bindings = { ... } }.
--
-- MySQL DDL commits implicitly, so a migration cannot be wrapped in a
-- transaction: each migration is recorded right after its statements succeed
-- and the batch stops at the first failure. A migration with several
-- statements that fails halfway stays partially applied and unrecorded.
local Sql = require("crescent.database.sql")

local Migrator = {}
Migrator.__index = Migrator

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- adapter defaults to Database.default(). options: path ("migrations"),
-- table ("migrations"), migrations (explicit list instead of files), log(fn).
function Migrator.new(adapter, options)
    options = options or {}
    local table_name = options.table or "migrations"
    return setmetatable({
        adapter = adapter,
        path = options.path or "migrations",
        table_name = table_name,
        table_sql = Sql.identifier(table_name),
        migrations = options.migrations,
        log = options.log or function() end,
    }, Migrator)
end

function Migrator:_db()
    if self.adapter then return self.adapter end
    return require("crescent.database").default()
end

function Migrator:ensure_table()
    return self:_db():execute("CREATE TABLE IF NOT EXISTS " .. self.table_sql .. " ("
        .. "`id` INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, "
        .. "`migration` VARCHAR(255) NOT NULL UNIQUE, "
        .. "`batch` INT UNSIGNED NOT NULL, "
        .. "`executed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP"
        .. ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4")
end

local function validate(migration, name)
    if type(migration) ~= "table" then return nil, "migration " .. name .. " must return a table" end
    if type(migration.up) ~= "function" or type(migration.down) ~= "function" then
        return nil, "migration " .. name .. " requires up() and down()"
    end
    return migration
end

-- Sorted list of { name, path } (files) or { name, migration } (explicit).
function Migrator:discover()
    local entries = {}
    if self.migrations then
        for _, migration in ipairs(self.migrations) do
            if type(migration) ~= "table" or type(migration.name) ~= "string" then
                return nil, "migration requires a name"
            end
            entries[#entries + 1] = { name = migration.name, migration = migration }
        end
    else
        local handle = io.popen("ls -1 " .. shell_quote(self.path) .. " 2>/dev/null")
        if handle then
            for file in handle:lines() do
                local name = file:match("^([%w_%-]+)%.lua$")
                if name then entries[#entries + 1] = { name = name, path = self.path .. "/" .. file } end
            end
            handle:close()
        end
    end
    table.sort(entries, function(left, right) return left.name < right.name end)
    return entries
end

function Migrator:load(entry)
    if entry.migration then return validate(entry.migration, entry.name) end
    local chunk, load_err = loadfile(entry.path)
    if not chunk then return nil, "unable to load migration " .. entry.name .. ": " .. tostring(load_err) end
    local ok, migration = pcall(chunk)
    if not ok then return nil, "migration " .. entry.name .. " failed to load: " .. tostring(migration) end
    return validate(migration, entry.name)
end

-- Normalizes what up()/down() returned into a list of { sql, bindings }.
function Migrator.statements(result)
    if type(result) == "string" then return { { sql = result } } end
    if type(result) ~= "table" then return nil, "up()/down() must return SQL, a list of SQL, or {} for a no-op" end
    if type(result.sql) == "string" then return { result } end
    local statements = {}
    for index, item in ipairs(result) do
        if type(item) == "string" then
            statements[index] = { sql = item }
        elseif type(item) == "table" and type(item.sql) == "string" then
            statements[index] = item
        else
            return nil, "invalid migration statement #" .. index
        end
    end
    return statements
end

function Migrator:_run(migration, direction, name)
    local db = self:_db()
    local ok, result = pcall(migration[direction], db)
    if not ok then return nil, name .. " " .. direction .. "() raised: " .. tostring(result) end
    local statements, err = Migrator.statements(result)
    if not statements then return nil, name .. ": " .. err end
    for index, statement in ipairs(statements) do
        local executed, execute_err = db:execute(statement.sql, statement.bindings or {})
        if not executed then
            return nil, string.format("%s %s() statement #%d failed: %s", name, direction, index, tostring(execute_err))
        end
    end
    return true
end

-- Rows of the migrations table ordered by id.
function Migrator:applied()
    local ok, err = self:ensure_table()
    if not ok then return nil, err end
    return self:_db():query("SELECT `id`, `migration`, `batch`, `executed_at` FROM " .. self.table_sql .. " ORDER BY `id`")
end

-- Runs every pending migration in a new batch.
-- Returns { batch, migrated = { names } } or nil, err, { failed, migrated }.
function Migrator:migrate()
    local rows, err = self:applied()
    if not rows then return nil, err, { migrated = {} } end
    local done, batch = {}, 0
    for _, row in ipairs(rows) do
        done[row.migration] = true
        batch = math.max(batch, tonumber(row.batch) or 0)
    end
    batch = batch + 1

    local entries, discover_err = self:discover()
    if not entries then return nil, discover_err, { migrated = {} } end
    local migrated = {}
    for _, entry in ipairs(entries) do
        if not done[entry.name] then
            self.log("migrating", entry.name)
            local migration, load_err = self:load(entry)
            if not migration then return nil, load_err, { failed = entry.name, migrated = migrated, batch = batch } end
            local ok, run_err = self:_run(migration, "up", entry.name)
            if not ok then return nil, run_err, { failed = entry.name, migrated = migrated, batch = batch } end
            local recorded, record_err = self:_db():execute(
                "INSERT INTO " .. self.table_sql .. " (`migration`, `batch`) VALUES (?, ?)", { entry.name, batch })
            if not recorded then
                return nil, entry.name .. " ran but could not be recorded: " .. tostring(record_err),
                    { failed = entry.name, migrated = migrated, batch = batch }
            end
            migrated[#migrated + 1] = entry.name
            self.log("migrated", entry.name)
        end
    end
    return { batch = #migrated > 0 and batch or nil, migrated = migrated }
end

-- Reverts the last batch in reverse order.
-- Returns { batch, rolled_back = { names } } or nil, err, { failed, rolled_back }.
function Migrator:rollback()
    local rows, err = self:applied()
    if not rows then return nil, err, { rolled_back = {} } end
    local batch = 0
    for _, row in ipairs(rows) do batch = math.max(batch, tonumber(row.batch) or 0) end
    if batch == 0 then return { rolled_back = {} } end

    local entries, discover_err = self:discover()
    if not entries then return nil, discover_err, { rolled_back = {} } end
    local by_name = {}
    for _, entry in ipairs(entries) do by_name[entry.name] = entry end

    local rolled_back = {}
    for index = #rows, 1, -1 do
        local row = rows[index]
        if tonumber(row.batch) == batch then
            local name = row.migration
            local entry = by_name[name]
            local info = { failed = name, rolled_back = rolled_back, batch = batch }
            if not entry then return nil, "migration file for " .. name .. " not found", info end
            self.log("rolling_back", name)
            local migration, load_err = self:load(entry)
            if not migration then return nil, load_err, info end
            local ok, run_err = self:_run(migration, "down", name)
            if not ok then return nil, run_err, info end
            local removed, remove_err = self:_db():execute(
                "DELETE FROM " .. self.table_sql .. " WHERE `migration` = ?", { name })
            if not removed then
                return nil, name .. " was reverted but its record could not be removed: " .. tostring(remove_err), info
            end
            rolled_back[#rolled_back + 1] = name
            self.log("rolled_back", name)
        end
    end
    return { batch = batch, rolled_back = rolled_back }
end

-- List of { name, ran, batch, executed_at } for files and recorded rows.
function Migrator:status()
    local rows, err = self:applied()
    if not rows then return nil, err end
    local entries, discover_err = self:discover()
    if not entries then return nil, discover_err end
    local recorded, seen, result = {}, {}, {}
    for _, row in ipairs(rows) do recorded[row.migration] = row end
    for _, entry in ipairs(entries) do
        local row = recorded[entry.name]
        seen[entry.name] = true
        result[#result + 1] = {
            name = entry.name, ran = row ~= nil,
            batch = row and tonumber(row.batch), executed_at = row and row.executed_at,
        }
    end
    for _, row in ipairs(rows) do
        if not seen[row.migration] then
            result[#result + 1] = {
                name = row.migration, ran = true, missing = true,
                batch = tonumber(row.batch), executed_at = row.executed_at,
            }
        end
    end
    return result
end

return Migrator
