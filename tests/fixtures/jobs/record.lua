local log = require("tests.fixtures.jobs.log")

return {
    handle = function(payload, job)
        log.calls[#log.calls + 1] = { payload = payload, attempts = job.attempts, queue = job.queue, id = job.id }
    end,
}
