local HealthAction = {}

function HealthAction.show(ctx)
    return ctx:json(200, {
        status = "ok",
        service = "{{project}}",
        environment = ctx.config.environment,
        timestamp = ngx and ngx.time() or os.time(),
    })
end

return HealthAction
