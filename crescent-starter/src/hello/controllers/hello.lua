-- src/hello/controllers/hello.lua
-- Controller para Hello

local service = require("src.hello.services.hello")
local HelloController = {}

function HelloController:index(ctx)
    local result = service:getAll()
    return ctx.json(200, result)
end

function HelloController:show(ctx)
    local id = ctx.params.id
    local result = service:getById(id)
    
    if result then
        return ctx.json(200, result)
    else
        return ctx.json(404, { error = "Not found" })
    end
end

function HelloController:create(ctx)
    local body = ctx.body or {}
    local result = service:create(body)
    return ctx.json(201, result)
end

function HelloController:update(ctx)
    local id = ctx.params.id
    local body = ctx.body or {}
    local result = service:update(id, body)
    
    if result then
        return ctx.json(200, result)
    else
        return ctx.json(404, { error = "Not found" })
    end
end

function HelloController:delete(ctx)
    local id = ctx.params.id
    local success = service:delete(id)
    
    if success then
        return ctx.no_content()
    else
        return ctx.json(404, { error = "Not found" })
    end
end

return HelloController
