-- Key/value cache with two drivers, exposed as `ctx.cache` / `app.cache`
-- when config.cache is set:
--
--   cache = {
--       driver = "shared",          -- or "redis" (config.redis)
--       prefix = "myapp:cache:",
--       ttl = 3600,                 -- default TTL in seconds; 0 = no expiry
--       dict = "crescent_cache",    -- lua_shared_dict for the shared driver
--   }
--
--   ctx.cache:set("user:1", user, 300)
--   ctx.cache:get("user:1")
--   ctx.cache:remember("stats", 60, function() return expensive() end)
--
-- shared: an ngx.shared dict — memory shared by the nginx workers of one
--   server, LRU-evicted when full, lost on restart. No extra service.
-- redis: shared by every server/container, survives app restarts.
--
-- Values are stored as JSON, so tables, strings, numbers and booleans round
-- trip; nil cannot be cached (`remember` does not store a nil result).
-- Backend errors never raise: reads return nil (a miss) plus the error, so a
-- cache outage degrades to recomputing.
local json = require("crescent.json")

local Cache = {}
Cache.__index = Cache

local DEFAULTS = {
    driver = "shared",
    prefix = "crescent:cache:",
    ttl = 3600,
    dict = "crescent_cache",
    lock_ttl = 10,
    lock_wait = 5,
}

local function encode(value)
    if value == nil then return nil, "cannot cache nil" end
    local text, err = json.encode(value)
    if not text then return nil, "cache value is not JSON-serializable: " .. tostring(err) end
    return text
end

local function decode(raw)
    if raw == nil then return nil end
    -- Counters (incr) are stored as numbers.
    if type(raw) == "number" then return raw end
    local value = json.decode(raw)
    if value == nil then return nil, "corrupt cache entry" end
    return value
end

local function sleep(seconds)
    if not (ngx and ngx.sleep) then return false end
    return pcall(ngx.sleep, seconds)
end

-- Drivers: get, set, add, delete, incr, expire, flush. Keys arrive prefixed;
-- ttl is in seconds (0 = no expiry).

local SharedDriver = {}
SharedDriver.__index = SharedDriver

function SharedDriver.new(settings)
    return setmetatable({ name = settings.dict }, SharedDriver)
end

function SharedDriver:dict()
    local dict = ngx and ngx.shared and ngx.shared[self.name]
    if not dict then
        error("cache driver \"shared\" requires `lua_shared_dict " .. self.name .. " 32m;` in nginx.conf", 3)
    end
    return dict
end

function SharedDriver:get(key)
    return self:dict():get(key)
end

function SharedDriver:set(key, raw, ttl)
    -- set (not safe_set) evicts least-recently-used entries when full.
    local ok, err = self:dict():set(key, raw, ttl)
    if not ok then return nil, err end
    return true
end

function SharedDriver:add(key, raw, ttl)
    local ok, err = self:dict():add(key, raw, ttl)
    if ok then return true end
    if err == "exists" then return false end
    return nil, err
end

function SharedDriver:delete(key)
    self:dict():delete(key)
    return true
end

function SharedDriver:incr(key, by, ttl)
    -- init_ttl only applies when the key is created.
    return self:dict():incr(key, by, 0, ttl > 0 and ttl or nil)
end

-- Removes every entry in the dict: give the cache a dict of its own.
function SharedDriver:flush()
    local dict = self:dict()
    dict:flush_all()
    dict:flush_expired()
    return true
end

local RedisDriver = {}
RedisDriver.__index = RedisDriver

function RedisDriver.new(settings, redis)
    if not redis then error("cache driver \"redis\" requires config.redis", 3) end
    return setmetatable({ redis = redis, prefix = settings.prefix }, RedisDriver)
end

local function expiry_args(args, ttl)
    if ttl > 0 then
        args[#args + 1] = "PX"
        args[#args + 1] = math.max(1, math.floor(ttl * 1000))
    end
    return args
end

function RedisDriver:get(key)
    return self.redis:command("get", key)
end

function RedisDriver:set(key, raw, ttl)
    local result, err = self.redis:command("set", unpack(expiry_args({ key, raw }, ttl)))
    if not result then return nil, err end
    return true
end

function RedisDriver:add(key, raw, ttl)
    local args = expiry_args({ key, raw }, ttl)
    args[#args + 1] = "NX"
    local result, err = self.redis:command("set", unpack(args))
    if err then return nil, err end
    return result == "OK"
end

function RedisDriver:delete(key)
    local result, err = self.redis:command("del", key)
    if result == nil then return nil, err end
    return true
end

local INCR_SCRIPT = [[
local value = redis.call('incrbyfloat', KEYS[1], ARGV[1])
if tonumber(ARGV[2]) > 0 and redis.call('pttl', KEYS[1]) == -1 then
    redis.call('pexpire', KEYS[1], ARGV[2])
end
return value
]]

function RedisDriver:incr(key, by, ttl)
    local result, err = self.redis:eval(INCR_SCRIPT, { key }, { by, math.floor(ttl * 1000) })
    if result == nil then return nil, err end
    return tonumber(result)
end

-- Deletes the keys under the cache prefix (SCAN + UNLINK, never FLUSHDB).
function RedisDriver:flush()
    if not self.prefix or self.prefix == "" then
        return nil, "refusing to flush a redis cache without a prefix"
    end
    local pattern = self.prefix:gsub("[%*%?%[%]\\]", "\\%0") .. "*"
    return self.redis:with(function(red)
        local cursor = "0"
        repeat
            local reply, err = red:scan(cursor, "MATCH", pattern, "COUNT", 500)
            if not reply then return nil, "redis: " .. tostring(err) end
            cursor = reply[1]
            if #reply[2] > 0 then
                local deleted, del_err = red:unlink(unpack(reply[2]))
                if not deleted then return nil, "redis: " .. tostring(del_err) end
            end
        until cursor == "0"
        return true
    end)
end

-- Cache ---------------------------------------------------------------------

local DRIVERS = { shared = SharedDriver, redis = RedisDriver }

-- options.redis: a crescent.redis client (required by the redis driver);
-- options.driver: a custom driver object (tests, other backends).
function Cache.new(config, options)
    config = config or {}
    options = options or {}
    if type(config) ~= "table" then error("cache config must be a table", 2) end
    local settings = {}
    for key, value in pairs(DEFAULTS) do settings[key] = value end
    for key, value in pairs(config) do settings[key] = value end
    if type(settings.ttl) ~= "number" or settings.ttl < 0 then error("cache ttl must be a number >= 0", 2) end

    local driver = options.driver
    if not driver then
        local Driver = DRIVERS[settings.driver]
        if not Driver then error("unknown cache driver: " .. tostring(settings.driver), 2) end
        driver = Driver.new(settings, options.redis)
    end
    return setmetatable({ settings = settings, driver = driver, prefix = settings.prefix }, Cache)
end

function Cache:key(key)
    if type(key) ~= "string" or key == "" then error("cache key must be a non-empty string", 3) end
    return self.prefix .. key
end

function Cache:ttl(ttl)
    if ttl == nil then return self.settings.ttl end
    if type(ttl) ~= "number" or ttl < 0 then error("cache ttl must be a number >= 0", 3) end
    return ttl
end

-- value, or nil on a miss (plus an error when the backend failed).
function Cache:get(key, default)
    local raw, err = self.driver:get(self:key(key))
    if raw == nil then
        if default ~= nil then return default, err end
        return nil, err
    end
    local value, decode_err = decode(raw)
    if value == nil then return default, decode_err end
    return value
end

function Cache:has(key)
    return self:get(key) ~= nil
end

function Cache:set(key, value, ttl)
    local raw, err = encode(value)
    if not raw then error(err, 2) end
    return self.driver:set(self:key(key), raw, self:ttl(ttl))
end

-- Stores only when the key is absent: true if stored, false if it existed.
function Cache:add(key, value, ttl)
    local raw, err = encode(value)
    if not raw then error(err, 2) end
    return self.driver:add(self:key(key), raw, self:ttl(ttl))
end

function Cache:delete(key)
    return self.driver:delete(self:key(key))
end

Cache.forget = Cache.delete

-- Reads and deletes.
function Cache:pull(key, default)
    local value, err = self:get(key, default)
    self:delete(key)
    return value, err
end

-- Atomic counter (created at 0). ttl applies when the counter is created.
function Cache:incr(key, by, ttl)
    by = by or 1
    if type(by) ~= "number" then error("cache incr step must be a number", 2) end
    return self.driver:incr(self:key(key), by, self:ttl(ttl))
end

function Cache:decr(key, by, ttl)
    return self:incr(key, -(by or 1), ttl)
end

function Cache:flush()
    return self.driver:flush()
end

-- Returns the cached value, or calls fn(), caches a non-nil result and
-- returns it. Only one caller per key computes at a time (a short lock in
-- the cache itself); concurrent callers wait up to `lock_wait` seconds for
-- the value, then compute it themselves. Errors raised by fn propagate.
function Cache:remember(key, ttl, fn)
    if type(ttl) == "function" then ttl, fn = nil, ttl end
    if type(fn) ~= "function" then error("cache remember requires a function", 2) end
    local value = self:get(key)
    if value ~= nil then return value end

    local settings = self.settings
    local lock_key = self:key(key) .. ":lock"
    local locked = self.driver:add(lock_key, "1", settings.lock_ttl)
    if locked == false then
        local waited, step = 0, 0.02
        while waited < settings.lock_wait do
            if not sleep(step) then break end
            waited = waited + step
            step = math.min(step * 2, 0.2)
            value = self:get(key)
            if value ~= nil then return value end
            if self.driver:get(lock_key) == nil then break end
        end
    end

    local ok, result = pcall(fn)
    if ok and result ~= nil then
        local raw = encode(result)
        if raw then self.driver:set(self:key(key), raw, self:ttl(ttl)) end
    end
    if locked then self.driver:delete(lock_key) end
    if not ok then error(result, 0) end
    return result
end

return Cache
