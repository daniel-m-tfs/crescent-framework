package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")

local function run_tests_with_ngx_body()
    local previous_ngx = ngx
    local body_read = false
    local response_body
    local fake_ngx = {
        req = {
            get_headers = function() return { ["Content-Type"] = "text/plain" } end,
            get_method = function() return "POST" end,
            get_uri_args = function() return { source = "test" } end,
            read_body = function() body_read = true end,
            get_body_data = function()
                tests.assertTrue(body_read, "request body must be read before it is accessed")
                return "payload"
            end,
        },
        var = { uri = "/echo" },
        header = {},
        say = function(value) response_body = value end,
    }

    ngx = fake_ngx
    local app = Crescent.new({ debug = false })
    app:post("/echo", function(ctx)
        tests.assertEquals(ctx.body, "payload")
        tests.assertEquals(ctx.query.source, "test")
        tests.assertEquals(ctx:get_header("content-type"), "text/plain")
        return ctx:text(201, ctx.body)
    end)

    local ok, err = pcall(app.run, app)
    ngx = previous_ngx
    tests.assertTrue(ok, tostring(err))
    tests.assertEquals(fake_ngx.status, 201)
    tests.assertEquals(response_body, "payload")
    tests.assertContains(fake_ngx.header["X-Request-Id"], "crescent-")
end

local function run_tests_with_json_body()
    local previous_ngx = ngx
    local response_body
    local fake_ngx = {
        req = {
            get_headers = function() return { ["Content-Type"] = "application/json; charset=utf-8" } end,
            get_method = function() return "POST" end,
            get_uri_args = function() return {} end,
            read_body = function() end,
            get_body_data = function() return '{"name":"Ada"}' end,
        },
        var = { uri = "/json" },
        header = {},
        say = function(value) response_body = value end,
    }

    ngx = fake_ngx
    local app = Crescent.new({ debug = false })
    app:post("/json", function(ctx)
        tests.assertEquals(ctx.body.name, "Ada")
        tests.assertEquals(ctx.raw_body, '{"name":"Ada"}')
        return ctx:json(200, { received = ctx.body.name })
    end)
    local ok, err = pcall(app.run, app)
    ngx = previous_ngx
    tests.assertTrue(ok, tostring(err))
    tests.assertEquals(fake_ngx.status, 200)
    tests.assertContains(response_body, '"received":"Ada"')

    local malformed_ngx = {}
    for key, value in pairs(fake_ngx) do malformed_ngx[key] = value end
    malformed_ngx.req = {}
    for key, value in pairs(fake_ngx.req) do malformed_ngx.req[key] = value end
    malformed_ngx.req.get_body_data = function() return '{"name":' end
    malformed_ngx.header = {}
    local malformed_app = Crescent.new({ debug = false })
    local action_called = false
    malformed_app:post("/json", function()
        action_called = true
    end)
    ngx = malformed_ngx
    local malformed_ok, malformed_err = pcall(malformed_app.run, malformed_app)
    ngx = previous_ngx
    tests.assertTrue(malformed_ok, tostring(malformed_err))
    tests.assertEquals(malformed_ngx.status, 400)
    tests.assertFalse(action_called)
end

local function run_tests_with_form_body()
    local previous_ngx = ngx
    local response_body
    local fake_ngx = {
        req = {
            get_headers = function() return { ["Content-Type"] = "application/x-www-form-urlencoded" } end,
            get_method = function() return "POST" end,
            get_uri_args = function() return {} end,
            read_body = function() end,
            get_body_data = function() return "name=Ada+Lovelace&tag=lua&tag=web%2Fapp" end,
        },
        var = { uri = "/form" },
        header = {},
        say = function(value) response_body = value end,
    }

    ngx = fake_ngx
    local app = Crescent.new({ debug = false })
    app:post("/form", function(ctx)
        tests.assertEquals(ctx.body.name, "Ada Lovelace")
        tests.assertTableEquals(ctx.body.tag, { "lua", "web/app" })
        return ctx:json(200, { name = ctx.body.name })
    end)
    local ok, err = pcall(app.run, app)
    ngx = previous_ngx
    tests.assertTrue(ok, tostring(err))
    tests.assertEquals(fake_ngx.status, 200)
    tests.assertContains(response_body, '"name":"Ada Lovelace"')

    local malformed_ngx = {}
    for key, value in pairs(fake_ngx) do malformed_ngx[key] = value end
    malformed_ngx.req = {}
    for key, value in pairs(fake_ngx.req) do malformed_ngx.req[key] = value end
    malformed_ngx.req.get_body_data = function() return "name=%ZZ" end
    malformed_ngx.header = {}
    local malformed_app = Crescent.new({ debug = false })
    malformed_app:post("/form", function() error("must not run") end)
    ngx = malformed_ngx
    local malformed_ok, malformed_err = pcall(malformed_app.run, malformed_app)
    ngx = previous_ngx
    tests.assertTrue(malformed_ok, tostring(malformed_err))
    tests.assertEquals(malformed_ngx.status, 400)
end

local function application_tests()
    local app = Crescent.new({ debug = false })
    app:get("/health", function(ctx)
        return ctx:json(200, { status = "ok" })
    end)

    local writer = { headers = {}, sent = false }
    app:handle({ method = "GET", path = "/health", headers = {}, query = {}, request_id = "test-request-1" }, writer)
    tests.assertEquals(writer.status, 200, "health action must return 200")
    tests.assertEquals(writer.headers["X-Request-Id"], "test-request-1")
    tests.assertContains(writer.body, '"status":"ok"', "health body must be JSON")

    local missing = { headers = {}, sent = false }
    app:handle({ method = "GET", path = "/missing", headers = {}, query = {} }, missing)
    tests.assertEquals(missing.status, 404, "missing route must return 404")
    tests.assertContains(missing.body, '"code":"route_not_found"')

    local wrong_method = { headers = {}, sent = false }
    app:handle({ method = "POST", path = "/health", headers = {}, query = {} }, wrong_method)
    tests.assertEquals(wrong_method.status, 405, "wrong method must return 405")
    tests.assertEquals(wrong_method.headers.Allow, "GET", "405 must expose Allow")
    tests.assertContains(wrong_method.body, '"code":"method_not_allowed"')

    local grouped = Crescent.new({ debug = false })
    grouped:group("/api", function(grouped_app)
        grouped_app:get("/health", function(ctx)
            return ctx:text(200, "grouped")
        end, "api.health")
    end)
    tests.assertEquals(grouped:route("api.health"), "/api/health")
    local grouped_writer = { headers = {}, sent = false }
    grouped:handle({ method = "GET", path = "/api/health", headers = {}, query = {} }, grouped_writer)
    tests.assertEquals(grouped_writer.body, "grouped", "application groups must prefix routes")

    local validated = Crescent.new({ debug = false })
    local action_called = false
    validated:post("/users", validated:validated({
        name = { required = true, string = true, min_length = 3 },
    }, function(ctx)
        action_called = true
        return ctx:text(201, "created")
    end))
    local invalid_writer = { headers = {}, sent = false }
    validated:handle({
        method = "POST", path = "/users", headers = {}, query = {}, body = { name = "x" },
    }, invalid_writer)
    tests.assertEquals(invalid_writer.status, 422, "invalid input must return 422")
    tests.assertContains(invalid_writer.body, '"code":"validation_failed"')
    tests.assertFalse(action_called, "invalid input must not execute the action")

    local valid_writer = { headers = {}, sent = false }
    validated:handle({
        method = "POST", path = "/users", headers = {}, query = {}, body = { name = "Ada" },
    }, valid_writer)
    tests.assertEquals(valid_writer.status, 201, "valid input must execute the action")
    tests.assertTrue(action_called, "valid input must execute the action")

    local view_app = Crescent.new({ debug = false, views_root = "tests/fixtures/views" })
    view_app:get("/page", function(ctx)
        return ctx:view("hello.etlua", { name = "Ada", trusted = "<b>ok</b>" })
    end)
    local view_writer = { headers = {}, sent = false }
    view_app:handle({ method = "GET", path = "/page", headers = {}, query = {} }, view_writer)
    tests.assertEquals(view_writer.status, 200)
    tests.assertEquals(view_writer.headers["Content-Type"], "text/html; charset=utf-8")
    tests.assertContains(view_writer.body, "Ada")

    local failed = { headers = {}, sent = false }
    local broken = Crescent.new({ debug = false })
    broken:get("/broken", function() error("secret details") end)
    broken:handle({ method = "GET", path = "/broken", headers = {}, query = {} }, failed)
    tests.assertEquals(failed.status, 500, "action exception must return 500")
    tests.assertContains(failed.body, '"code":"internal_error"')
    tests.assertNotContains(failed.body, "secret details", "production error must hide details")

    local custom = Crescent.new({
        debug = false,
        error_handler = function(ctx, err)
            return ctx:error(503, "temporarily unavailable", { request_error = tostring(err) }, "service_unavailable")
        end,
    })
    custom:get("/custom-error", function() error("database offline") end)
    local custom_writer = { headers = {}, sent = false }
    custom:handle({ method = "GET", path = "/custom-error", headers = {}, query = {} }, custom_writer)
    tests.assertEquals(custom_writer.status, 503)
    tests.assertContains(custom_writer.body, '"code":"service_unavailable"')
    tests.assertContains(custom_writer.body, "database offline")

    local nil_handler = Crescent.new({
        debug = false,
        error_handler = function() end,
    })
    nil_handler:get("/fallback", function() error("private failure") end)
    local nil_writer = { headers = {}, sent = false }
    nil_handler:handle({ method = "GET", path = "/fallback", headers = {}, query = {} }, nil_writer)
    tests.assertEquals(nil_writer.status, 500)
    tests.assertContains(nil_writer.body, '"code":"internal_error"')
    tests.assertNotContains(nil_writer.body, "private failure")

    local invalid_id_writer = { headers = {}, sent = false }
    app:handle({ method = "GET", path = "/missing", headers = {}, query = {}, request_id = "bad id" }, invalid_id_writer)
    tests.assertContains(invalid_id_writer.headers["X-Request-Id"], "crescent-")

    local middleware_app = Crescent.new({ debug = false })
    local order = {}
    local action_executed = false
    middleware_app:use(function(ctx, next)
        order[#order + 1] = "before"
        ctx.state.authenticated = true
        local result = next()
        order[#order + 1] = "after"
        return result
    end)
    middleware_app:get("/middleware", function(ctx)
        action_executed = ctx.state.authenticated
        order[#order + 1] = "action"
        return ctx:text(200, "ok")
    end)
    local middleware_writer = { headers = {}, sent = false }
    middleware_app:handle({ method = "GET", path = "/middleware", headers = {}, query = {} }, middleware_writer)
    tests.assertTableEquals(order, { "before", "action", "after" })
    tests.assertTrue(action_executed, "middleware state must reach the action")

    local blocked_app = Crescent.new({ debug = false })
    local blocked_action = false
    blocked_app:use(function(ctx)
        return ctx:error(401, "unauthorized", nil, "unauthorized")
    end)
    blocked_app:get("/blocked", function(ctx)
        blocked_action = true
        return ctx:text(200, "unexpected")
    end)
    local blocked_writer = { headers = {}, sent = false }
    blocked_app:handle({ method = "GET", path = "/blocked", headers = {}, query = {} }, blocked_writer)
    tests.assertEquals(blocked_writer.status, 401)
    tests.assertFalse(blocked_action, "short-circuited middleware must prevent action")

    run_tests_with_ngx_body()
    run_tests_with_json_body()
    run_tests_with_form_body()
end

assert(tests.runSuite("Application", { handling = application_tests }))
