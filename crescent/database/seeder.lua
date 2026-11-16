-- Database seeders: `seeds/<name>.lua` files returning `function(db) ... end`.
-- Seeders run in name order (prefix them with numbers to control it), each in
-- its own transaction: a seeder either applies completely or not at all.
-- They are not recorded anywhere, so write them to be idempotent (e.g. look
-- the row up before creating it) when they may run more than once.
local Seeder = {}
Seeder.__index = Seeder

local NAME_PATTERN = "^[%w_%-]+$"

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- options: path (default "seeds"), seeds = { { name =, run = fn } } (tests).
function Seeder.new(adapter, options)
    if type(adapter) ~= "table" or type(adapter.transaction) ~= "function" then
        error("seeder requires a database adapter with transaction()", 2)
    end
    options = options or {}
    return setmetatable({
        adapter = adapter,
        path = options.path or "seeds",
        seeds = options.seeds,
        log = options.log or function() end,
    }, Seeder)
end

function Seeder:discover()
    if self.seeds then
        local entries = {}
        for _, seed in ipairs(self.seeds) do entries[#entries + 1] = seed end
        table.sort(entries, function(left, right) return left.name < right.name end)
        return entries
    end
    local entries = {}
    local handle = io.popen("ls -1 " .. shell_quote(self.path) .. " 2>/dev/null")
    if handle then
        for file in handle:lines() do
            local name = file:match("^([%w_%-]+)%.lua$")
            if name then entries[#entries + 1] = { name = name, path = self.path .. "/" .. file } end
        end
        handle:close()
    end
    table.sort(entries, function(left, right) return left.name < right.name end)
    return entries
end

local function load_seed(entry)
    if entry.run then return entry.run end
    local chunk, load_err = loadfile(entry.path)
    if not chunk then return nil, "unable to load seeder " .. entry.name .. ": " .. tostring(load_err) end
    local ok, seed = pcall(chunk)
    if not ok then return nil, "seeder " .. entry.name .. " failed to load: " .. tostring(seed) end
    if type(seed) == "table" and type(seed.run) == "function" then seed = seed.run end
    if type(seed) ~= "function" then return nil, "seeder " .. entry.name .. " must return a function" end
    return seed
end

-- Runs every seeder, or only `name`. Stops at the first failure.
-- Returns { seeded = { names } } or nil, err, { seeded = { names } }.
function Seeder:run(name)
    if name ~= nil and (type(name) ~= "string" or not name:match(NAME_PATTERN)) then
        return nil, "invalid seeder name: " .. tostring(name), { seeded = {} }
    end
    local seeded = {}
    local found = false
    for _, entry in ipairs(self:discover()) do
        if name == nil or entry.name == name then
            found = true
            local seed, load_err = load_seed(entry)
            if not seed then return nil, load_err, { seeded = seeded } end
            self.log("seeding", entry.name)
            -- Returning false or `nil, err` (or raising) rolls the seeder back.
            local ok, err = self.adapter:transaction(seed)
            if ok == nil or ok == false then
                return nil, "seeder " .. entry.name .. " failed: " .. tostring(err), { seeded = seeded }
            end
            seeded[#seeded + 1] = entry.name
        end
    end
    if name ~= nil and not found then
        return nil, "seeder not found: " .. name, { seeded = seeded }
    end
    return { seeded = seeded }
end

return Seeder
