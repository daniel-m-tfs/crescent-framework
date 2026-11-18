-- Queue driver on Redis (config.redis). Durable and shared by every app
-- server and worker process (`lua cli.lua queue:work`).
--
-- Keys per queue (the {name} hash tag keeps them in one Redis Cluster slot):
--   <prefix>{name}            ready list (RPUSH / LPOP)
--   <prefix>{name}:delayed    zset, score = available at
--   <prefix>{name}:reserved   zset, score = reservation expiry
--   <prefix>{name}:attempts   hash, job id -> attempts
--   <prefix>{name}:failed     list, newest first
-- A reserved job whose worker died, or that runs longer than its timeout,
-- returns to the ready list when the reservation expires (at-least-once
-- delivery: make handlers idempotent). Job strings are never re-encoded
-- inside Redis, so payload numbers keep their exact text.
local Redis = require("crescent.redis")

local RedisQueue = {}
RedisQueue.__index = RedisQueue

local POP = [[
local now = tonumber(ARGV[1])
local function migrate(from)
    local due = redis.call('zrangebyscore', from, '-inf', now, 'limit', 0, 100)
    for i = 1, #due do
        redis.call('zrem', from, due[i])
        redis.call('rpush', KEYS[1], due[i])
    end
end
migrate(KEYS[2])
migrate(KEYS[3])
local job = redis.call('lpop', KEYS[1])
if not job then return false end
local record = cjson.decode(job)
local attempts = redis.call('hincrby', KEYS[4], record.id, 1)
local timeout = tonumber(record.timeout) or tonumber(ARGV[2])
redis.call('zadd', KEYS[3], now + timeout, job)
return { job, attempts }
]]

local ACK = [[
redis.call('zrem', KEYS[1], ARGV[1])
redis.call('hdel', KEYS[2], ARGV[2])
return 1
]]

local RELEASE = [[
redis.call('zrem', KEYS[1], ARGV[1])
redis.call('zadd', KEYS[2], ARGV[2], ARGV[1])
return 1
]]

local FAIL = [[
redis.call('zrem', KEYS[1], ARGV[1])
redis.call('hdel', KEYS[2], ARGV[2])
redis.call('lpush', KEYS[3], ARGV[3])
redis.call('ltrim', KEYS[3], 0, tonumber(ARGV[4]) - 1)
return 1
]]

local RETRY = [[
local entries = redis.call('lrange', KEYS[1], 0, -1)
local count = 0
for i = #entries, 1, -1 do
    local ok, entry = pcall(cjson.decode, entries[i])
    if ok and type(entry) == 'table' and (ARGV[1] == '' or entry.id == ARGV[1]) then
        redis.call('lrem', KEYS[1], 1, entries[i])
        redis.call('rpush', KEYS[2], entry.job)
        count = count + 1
    end
end
return count
]]

function RedisQueue.new(settings, redis)
    if not redis then error("queue driver \"redis\" requires config.redis", 3) end
    return setmetatable({
        redis = redis,
        prefix = settings.prefix,
        timeout = settings.timeout,
        failed_limit = settings.failed_limit,
    }, RedisQueue)
end

function RedisQueue:keys(queue)
    local base = self.prefix .. "{" .. queue .. "}"
    return {
        ready = base,
        delayed = base .. ":delayed",
        reserved = base .. ":reserved",
        attempts = base .. ":attempts",
        failed = base .. ":failed",
    }
end

local function ok_or_error(result, err)
    if result == nil then return nil, err end
    return true
end

function RedisQueue:push(queue, raw, delay, now)
    local keys = self:keys(queue)
    if delay > 0 then return ok_or_error(self.redis:command("zadd", keys.delayed, now + delay, raw)) end
    return ok_or_error(self.redis:command("rpush", keys.ready, raw))
end

function RedisQueue:pop(queue, now)
    local keys = self:keys(queue)
    local result, err = self.redis:eval(POP, { keys.ready, keys.delayed, keys.reserved, keys.attempts },
        { now, self.timeout })
    if err then return nil, err end
    if type(result) ~= "table" or result[1] == nil then return nil end
    return result[1], tonumber(result[2])
end

function RedisQueue:ack(queue, raw, record)
    local keys = self:keys(queue)
    return ok_or_error(self.redis:eval(ACK, { keys.reserved, keys.attempts }, { raw, record.id }))
end

function RedisQueue:release(queue, raw, _, delay, now)
    local keys = self:keys(queue)
    return ok_or_error(self.redis:eval(RELEASE, { keys.reserved, keys.delayed }, { raw, now + delay }))
end

function RedisQueue:fail(queue, raw, record, entry)
    local keys = self:keys(queue)
    return ok_or_error(self.redis:eval(FAIL, { keys.reserved, keys.attempts, keys.failed },
        { raw, record.id, entry, self.failed_limit }))
end

function RedisQueue:size(queue)
    local keys = self:keys(queue)
    return self.redis:with(function(red)
        red:init_pipeline()
        red:llen(keys.ready)
        red:zcard(keys.delayed)
        red:zcard(keys.reserved)
        red:llen(keys.failed)
        local results, err = red:commit_pipeline()
        if not results then return nil, "redis: " .. tostring(err) end
        for index = 1, 4 do
            if type(results[index]) ~= "number" then
                return nil, "redis: " .. tostring(results[index] and results[index][2] or "pipeline failed")
            end
        end
        return { ready = results[1], delayed = results[2], reserved = results[3], failed = results[4] }
    end)
end

function RedisQueue:failed(queue, limit)
    local entries, err = self.redis:command("lrange", self:keys(queue).failed, 0, limit - 1)
    if not entries then return nil, err end
    return entries
end

function RedisQueue:retry(queue, id)
    local keys = self:keys(queue)
    local count, err = self.redis:eval(RETRY, { keys.failed, keys.ready }, { id or "" })
    if count == nil then return nil, err end
    return tonumber(count)
end

function RedisQueue:clear_failed(queue)
    local key = self:keys(queue).failed
    return self.redis:with(function(red)
        local count = red:llen(key)
        red:del(key)
        return Redis.null_to_nil(count) or 0
    end)
end

return RedisQueue
