local HelloController = {}

-- GET / — HTML page rendered from views/hello/index.etlua inside views/layout.etlua.
function HelloController.index(ctx)
    return ctx:view("hello/index.etlua", {
        title = "{{project}}",
        environment = ctx.config.environment,
    }, { layout = "layout.etlua" })
end

-- GET /api/hello?name=Ada — JSON; `name` is validated by app:validated (422 when invalid).
function HelloController.greet(ctx)
    local name = ctx.query.name
    if name == nil or name == "" then name = "World" end
    return ctx:json(200, { message = "Hello, " .. name .. "!" })
end

return HelloController
