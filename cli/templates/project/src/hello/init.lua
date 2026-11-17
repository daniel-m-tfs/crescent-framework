local controller = require("src.hello.controllers.hello")

local Module = {}

function Module.register(app)
    app:get("/", controller.index, "hello.index")
    app:get("/api/hello", app:validated({
        name = { type = "string", min_length = 1, max_length = 50 },
    }, controller.greet, "query"), "hello.greet")
end

return Module
