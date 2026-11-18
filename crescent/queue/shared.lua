-- Queue driver on an ngx.shared dict (lua_shared_dict crescent_queue).
--
-- Jobs live in the memory of one OpenResty server and are processed by
-- workers running inside its nginx workers (crescent.queue start_embedded).
-- No extra service, but jobs are lost on restart and a separate worker
-- process (`queue:work`) cannot see them: use the redis driver for that.
--
-- Keys: r:<queue> ready list, d:<queue> delayed list ("<available_at>|job"),
-- f:<queue> failed list, a:<id> attempt counter. Lists are pushed on the
-- left and popped on the right (FIFO).
local json = require("crescent.json")

local Shared = {}
Shared.__index = Shared

-- Delayed jobs are scanned at most this often per worker and queue.
local MIGRATE_INTERVAL = 0.5

function Shared.new(settings)
    return setmetatable({ name = settings.dict, failed_limit = settings.failed_limit, migrated = {} }, Shared)
end

function Shared:dict()
    local dict = ngx and ngx.shared and ngx.shared[self.name]
    if not dict then
        error("queue driver \"shared\" requires `lua_shared_dict " .. self.name .. " 16m;` in nginx.conf "
            .. "and runs inside OpenResty only; use QUEUE_DRIVER=redis for a separate worker process", 3)
    end
    return dict
end

local function job_id(raw)
    local record = json.decode(raw)
    return type(record) == "table" and record.id or nil
end

function Shared:push(queue, raw, delay, now)
    local dict = self:dict()
    local length, err
    if delay > 0 then
        length, err = dict:lpush("d:" .. queue, string.format("%.3f|", now + delay) .. raw)
    else
        length, err = dict:lpush("r:" .. queue, raw)
    end
    if not length then return nil, "queue: " .. tostring(err) end
    return true
end

-- Moves due delayed jobs to the ready list. Every item is popped by exactly
-- one worker, so concurrent migrations never duplicate a job.
function Shared:migrate(queue, now)
    local last = self.migrated[queue]
    if last and now - last < MIGRATE_INTERVAL then return end
    self.migrated[queue] = now
    local dict = self:dict()
    local delayed, ready = "d:" .. queue, "r:" .. queue
    for _ = 1, dict:llen(delayed) or 0 do
        local item = dict:rpop(delayed)
        if not item then break end
        local at, raw = item:match("^([%d%.]+)|(.*)$")
        if raw and tonumber(at) <= now then
            dict:lpush(ready, raw)
        elseif raw then
            dict:lpush(delayed, item)
        end
    end
end

-- -> raw job, attempts (including this one) | nil
function Shared:pop(queue, now)
    self:migrate(queue, now)
    local dict = self:dict()
    local raw = dict:rpop("r:" .. queue)
    if not raw then return nil end
    local id = job_id(raw)
    local attempts = id and dict:incr("a:" .. id, 1, 0) or 1
    return raw, attempts
end

function Shared:ack(_, _, record)
    self:dict():delete("a:" .. record.id)
    return true
end

function Shared:release(queue, raw, _, delay, now)
    return self:push(queue, raw, delay, now)
end

function Shared:fail(queue, _, record, entry)
    local dict = self:dict()
    dict:delete("a:" .. record.id)
    local key = "f:" .. queue
    local length, err = dict:lpush(key, entry)
    if not length then return nil, "queue: " .. tostring(err) end
    while length > self.failed_limit do
        dict:rpop(key)
        length = length - 1
    end
    return true
end

function Shared:size(queue)
    local dict = self:dict()
    return {
        ready = dict:llen("r:" .. queue) or 0,
        delayed = dict:llen("d:" .. queue) or 0,
        reserved = 0,
        failed = dict:llen("f:" .. queue) or 0,
    }
end

-- Rotates the failed list (shared dicts have no LRANGE); keep(entry) decides
-- whether each entry stays. Returns the entries in newest-first order.
function Shared:scan_failed(queue, keep)
    local dict = self:dict()
    local key = "f:" .. queue
    local seen = {}
    for _ = 1, dict:llen(key) or 0 do
        local entry = dict:rpop(key)
        if not entry then break end
        if keep(entry) then dict:lpush(key, entry) end
        table.insert(seen, 1, entry)
    end
    return seen
end

function Shared:failed(queue, limit)
    local entries = self:scan_failed(queue, function() return true end)
    local result = {}
    for index = 1, math.min(limit, #entries) do result[index] = entries[index] end
    return result
end

function Shared:retry(queue, id, now)
    local count = 0
    self:scan_failed(queue, function(entry)
        local decoded = json.decode(entry)
        if type(decoded) ~= "table" or (id and decoded.id ~= id) then return true end
        self:push(queue, decoded.job, 0, now)
        count = count + 1
        return false
    end)
    return count
end

function Shared:clear_failed(queue)
    local dict = self:dict()
    local count = dict:llen("f:" .. queue) or 0
    dict:delete("f:" .. queue)
    return count
end

return Shared
