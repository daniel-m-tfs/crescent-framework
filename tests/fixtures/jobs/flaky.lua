-- Fails until attempt `payload.succeed_on`; `payload.soft` fails by returning false.
local log = require("tests.fixtures.jobs.log")

return {
    backoff = 0,
    handle = function(payload, job)
        log.calls[#log.calls + 1] = { attempts = job.attempts }
        if job.attempts < payload.succeed_on then
            if payload.soft then return false, "not yet" end
            error("attempt " .. job.attempts .. " failed")
        end
    end,
    failed = function(payload, err)
        log.failed[#log.failed + 1] = { payload = payload, err = err }
    end,
}
