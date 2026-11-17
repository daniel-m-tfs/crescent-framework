package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Logger = require("crescent.logger")
local json = require("crescent.json")
local Crescent = require("crescent")

local function capture()
    local lines = {}
    return lines, function(level, line) lines[#lines + 1] = { level = level, entry = json.decode(line) } end
end

local function redaction()
    local input = {
        user = "ada", password = "p4ss", nested = { DB_PASSWORD = "x", api_key = "k", ok = 1 },
        headers = { Authorization = "Bearer abc", Cookie = "s=1", ["X-Api-Key"] = "z" },
        refresh_token = "r",
    }
    local output = Logger.redact(input)
    tests.assertEquals(output.user, "ada")
    tests.assertEquals(output.password, Logger.REDACTED)
    tests.assertEquals(output.nested.DB_PASSWORD, Logger.REDACTED)
    tests.assertEquals(output.nested.api_key, Logger.REDACTED)
    tests.assertEquals(output.nested.ok, 1)
    tests.assertEquals(output.headers.Authorization, Logger.REDACTED)
    tests.assertEquals(output.headers.Cookie, Logger.REDACTED)
    tests.assertEquals(output.headers["X-Api-Key"], Logger.REDACTED)
    tests.assertEquals(output.refresh_token, Logger.REDACTED)
    tests.assertEquals(input.password, "p4ss", "input must not be modified")

    local circular = { name = "loop" }
    circular.self = circular
    tests.assertEquals(Logger.redact(circular).self, "[circular]")
    tests.assertEquals(Logger.redact({ cpf = "1" }, { "cpf" }).cpf, Logger.REDACTED)
end

local function levels_and_json_lines()
    local lines, sink = capture()
    local log = Logger.new({ level = "info", sink = sink, fields = { service = "test" } })
    log:debug("hidden")
    log:info("signed in", { user_id = 7, password = "x" })
    log:with({ request_id = "rid-1" }):error("boom")
    tests.assertEquals(#lines, 2)
    tests.assertEquals(lines[1].entry.msg, "signed in")
    tests.assertEquals(lines[1].entry.level, "info")
    tests.assertEquals(lines[1].entry.service, "test")
    tests.assertEquals(lines[1].entry.password, Logger.REDACTED)
    tests.assertEquals(lines[2].entry.request_id, "rid-1")
    tests.assertError(function() Logger.new({ level = "loud" }) end, "invalid log level")
end

local function application_uses_structured_logger()
    local lines, sink = capture()
    local app = Crescent.new({ logger = Logger.new({ sink = sink }) })
    app:get("/boom", function() error("kaput") end)
    local writer = { headers = {} }
    app:handle({ method = "GET", path = "/boom", headers = {}, query = {}, request_id = "rid-9" }, writer)
    tests.assertEquals(writer.status, 500)
    tests.assertEquals(#lines, 1)
    tests.assertEquals(lines[1].entry.level, "error")
    tests.assertEquals(lines[1].entry.request_id, "rid-9")
    tests.assertContains(lines[1].entry.msg, "kaput")
end

local function request_log_middleware()
    local lines, sink = capture()
    local app = Crescent.new({ logger = function() end })
    app:use(Crescent.middleware.request_log.create({
        logger = Logger.new({ sink = sink }),
        skip = function(ctx) return ctx.path == "/health" end,
    }))
    app:get("/users/{id}", function(ctx)
        ctx.state.user = { id = 3 }
        ctx.state.log:info("inside action")
        return ctx:json(200, { ok = true })
    end)
    app:get("/health", function(ctx) return ctx:text(200, "ok") end)
    local function get(path)
        local writer = { headers = {} }
        app:handle({ method = "GET", path = path, headers = {}, query = {}, request_id = "rid-2", remote_addr = "10.0.0.1" }, writer)
        return writer
    end
    get("/users/3")
    get("/missing")
    get("/health")
    tests.assertEquals(#lines, 3, "health requests are skipped")
    tests.assertEquals(lines[1].entry.msg, "inside action")
    tests.assertEquals(lines[1].entry.request_id, "rid-2")
    local request = lines[2].entry
    tests.assertEquals(request.msg, "request")
    tests.assertEquals(request.status, 200)
    tests.assertEquals(request.route, "/users/{id}")
    tests.assertEquals(request.user_id, 3)
    tests.assertEquals(request.remote_addr, "10.0.0.1")
    tests.assertType(request.duration_ms, "number")
    tests.assertEquals(lines[3].level, "warn", "4xx is logged as warn")
end

-- The logged status is the one sent after finalize, not a default 200.
local function request_log_logs_final_status()
    local lines, sink = capture()
    local app = Crescent.new({ logger = function() end })
    app:use(Crescent.middleware.request_log.create({ logger = Logger.new({ sink = sink }) }))
    app:get("/table", function() return { ok = true } end)
    app:get("/empty", function() end)
    app:get("/boom", function() error("kaput") end)
    local function get(path)
        local writer = { headers = {} }
        app:handle({ method = "GET", path = path, headers = {}, query = {} }, writer)
        return writer
    end
    tests.assertEquals(get("/table").status, 200)
    tests.assertEquals(get("/empty").status, 500)
    tests.assertEquals(get("/boom").status, 500)
    tests.assertEquals(#lines, 3)
    tests.assertEquals(lines[1].entry.status, 200)
    tests.assertEquals(lines[2].entry.status, 500)
    tests.assertEquals(lines[2].level, "error")
    tests.assertEquals(lines[3].entry.status, 500)
end

local function health_and_readiness()
    local healthy_db = { query = function() return { { ok = 1 } } end, execute = function() end,
        transaction = function() end, connect = function() end, close = function() end }
    local app = Crescent.new({ db = healthy_db, logger = function() end, environment = "test" })
    Crescent.health.register(app, { service = "svc" })
    local function get(path)
        local writer = { headers = {} }
        app:handle({ method = "GET", path = path, headers = {}, query = {} }, writer)
        return writer, json.decode(writer.body)
    end
    local live, live_body = get("/health")
    tests.assertEquals(live.status, 200)
    tests.assertEquals(live_body.service, "svc")
    tests.assertEquals(live_body.environment, "test")
    local ready, ready_body = get("/ready")
    tests.assertEquals(ready.status, 200)
    tests.assertEquals(ready_body.checks.database.status, "ok")

    healthy_db.query = function() return nil, "Access denied for user 'app' password=hunter2" end
    local down, down_body = get("/ready")
    tests.assertEquals(down.status, 503)
    tests.assertEquals(down_body.status, "not_ready")
    tests.assertEquals(down_body.checks.database.status, "failing")
    tests.assertNotContains(down.body, "hunter2", "check errors are hidden outside debug")

    local custom = Crescent.new({ logger = function() end })
    Crescent.health.register(custom, { checks = { cache = function() error("redis down") end } })
    local writer = { headers = {} }
    custom:handle({ method = "GET", path = "/ready", headers = {}, query = {} }, writer)
    tests.assertEquals(writer.status, 503)
end

assert(tests.runSuite("Observability", {
    redaction = redaction,
    levels_and_json_lines = levels_and_json_lines,
    application_uses_structured_logger = application_uses_structured_logger,
    request_log_middleware = request_log_middleware,
    request_log_logs_final_status = request_log_logs_final_status,
    health_and_readiness = health_and_readiness,
}))
