local HealthAction = {}

function HealthAction.show(ctx)
    return ctx:json(200, {
        status = "ok",
        service = "newcrescent",
        environment = "development",
        timestamp = os.time(),
    })
end

return HealthAction
