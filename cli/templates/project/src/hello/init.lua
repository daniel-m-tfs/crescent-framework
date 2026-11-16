local actions = require("src.hello.actions.hello")

local Module = {}

function Module.register(app)
    app:get("/", actions.index, "hello.index")
    app:get("/api/hello", app:validated({
        name = { type = "string", min_length = 1, max_length = 50 },
    }, actions.greet, "query"), "hello.greet")
end

return Module
