-- Pushes a follow-up job from inside a job.
return {
    handle = function(payload, job)
        job.dispatch("tests.fixtures.jobs.record", { from = job.id }, { queue = payload.queue })
    end,
}
