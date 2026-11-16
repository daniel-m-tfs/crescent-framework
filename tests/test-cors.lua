package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local cors = require("crescent.middleware.cors")

local function app_with(middleware)
    local app = Crescent.new({ logger = function() end })
    app:use(middleware)
    app:get("/items", function(ctx) return ctx:json(200, { ok = true }) end)
    app:post("/items", function(ctx) return ctx:json(201, { ok = true }) end)
    return app
end

local function request(app, method, headers, path)
    local writer = { headers = {}, sent = false }
    app:handle({ method = method, path = path or "/items", headers = headers or {}, query = {} }, writer)
    return writer
end

local function preflight(origin, method, request_headers)
    return {
        origin = origin,
        ["access-control-request-method"] = method or "POST",
        ["access-control-request-headers"] = request_headers,
    }
end

local ORIGIN = "https://app.example"

local suite = {
    -- Ported from the original tests/test-core.lua ------------------------
    wildcard_with_credentials_is_refused = function()
        tests.assertError(function() cors.create({ origin = "*", credentials = true }) end, "credentials")
        tests.assertError(function() cors.create({ credentials = true }) end, "credentials")
        tests.assertNoError(function() cors.create({ origins = { ORIGIN }, credentials = true }) end)
    end,

    -- New ---------------------------------------------------------------
    preflight_is_answered_before_routing = function()
        -- No OPTIONS route exists: without the middleware this would be 405.
        local plain = Crescent.new({ logger = function() end })
        plain:post("/items", function(ctx) return ctx:text(201, "x") end)
        tests.assertEquals(request(plain, "OPTIONS", preflight(ORIGIN)).status, 405)

        local app = app_with(cors.create({ origins = { ORIGIN }, max_age = 600 }))
        local writer = request(app, "OPTIONS", preflight(ORIGIN, "POST", "Content-Type, authorization"))
        tests.assertEquals(writer.status, 204)
        tests.assertEquals(writer.body, "")
        tests.assertEquals(writer.headers["Access-Control-Allow-Origin"], ORIGIN)
        tests.assertContains(writer.headers["Access-Control-Allow-Methods"], "POST")
        tests.assertContains(writer.headers["Access-Control-Allow-Headers"], "Authorization")
        tests.assertEquals(writer.headers["Access-Control-Max-Age"], "600")
        tests.assertContains(writer.headers.Vary, "Origin")
    end,

    preflight_validates_method_and_headers = function()
        local app = app_with(cors.create({ origins = { ORIGIN }, methods = { "GET", "POST" } }))
        local bad_method = request(app, "OPTIONS", preflight(ORIGIN, "DELETE"))
        tests.assertEquals(bad_method.status, 403)
        tests.assertContains(bad_method.body, '"code":"cors_method_not_allowed"')

        local bad_header = request(app, "OPTIONS", preflight(ORIGIN, "POST", "Content-Type, X-Secret"))
        tests.assertEquals(bad_header.status, 403)
        tests.assertContains(bad_header.body, '"code":"cors_header_not_allowed"')

        local safelisted = request(app, "OPTIONS", preflight(ORIGIN, "GET", "accept, accept-language"))
        tests.assertEquals(safelisted.status, 204)
    end,

    preflight_from_unknown_origin = function()
        local app = app_with(cors.create({ origins = { ORIGIN } }))
        local writer = request(app, "OPTIONS", preflight("https://evil.example"))
        tests.assertEquals(writer.status, 403)
        tests.assertContains(writer.body, '"code":"cors_origin_not_allowed"')
        tests.assertNil(writer.headers["Access-Control-Allow-Origin"])
    end,

    simple_request_reflects_matched_origin = function()
        local app = app_with(cors.create({ origins = { ORIGIN }, credentials = true, expose_headers = { "X-Request-Id" } }))
        local writer = request(app, "GET", { origin = ORIGIN })
        tests.assertEquals(writer.status, 200)
        tests.assertEquals(writer.headers["Access-Control-Allow-Origin"], ORIGIN)
        tests.assertEquals(writer.headers["Access-Control-Allow-Credentials"], "true")
        tests.assertEquals(writer.headers["Access-Control-Expose-Headers"], "X-Request-Id")
        tests.assertEquals(writer.headers.Vary, "Origin")
        tests.assertNil(writer.headers["Access-Control-Allow-Methods"], "only preflights list methods")
    end,

    unknown_origin_gets_no_cors_headers = function()
        local app = app_with(cors.create({ origins = { ORIGIN } }))
        local writer = request(app, "GET", { origin = "https://evil.example" })
        tests.assertEquals(writer.status, 200, "non-blocking policy lets the browser enforce CORS")
        tests.assertNil(writer.headers["Access-Control-Allow-Origin"])
        tests.assertEquals(writer.headers.Vary, "Origin")
    end,

    request_without_origin_passes_through = function()
        local app = app_with(cors.create({ origins = { ORIGIN } }))
        local writer = request(app, "GET")
        tests.assertEquals(writer.status, 200)
        tests.assertNil(writer.headers["Access-Control-Allow-Origin"])
        -- A plain OPTIONS without preflight headers reaches the router.
        tests.assertEquals(request(app, "OPTIONS", { origin = ORIGIN }).status, 405)
    end,

    wildcard_policy = function()
        local app = app_with(cors.default())
        local writer = request(app, "GET", { origin = "https://anything.example" })
        tests.assertEquals(writer.headers["Access-Control-Allow-Origin"], "*")
        tests.assertNil(writer.headers.Vary)
        tests.assertNil(writer.headers["Access-Control-Allow-Credentials"])
        tests.assertEquals(request(app, "OPTIONS", preflight("https://x.example", "PUT")).status, 204)
    end,

    origin_function = function()
        local app = app_with(cors.create({
            origins = function(origin) return origin:match("^https://[%w-]+%.example%.com$") ~= nil end,
            credentials = true,
        }))
        local ok = request(app, "GET", { origin = "https://tenant-1.example.com" })
        tests.assertEquals(ok.headers["Access-Control-Allow-Origin"], "https://tenant-1.example.com")
        local bad = request(app, "GET", { origin = "https://example.com.evil.net" })
        tests.assertNil(bad.headers["Access-Control-Allow-Origin"])
    end,

    strict_blocks_other_origins = function()
        local app = app_with(cors.strict({ ORIGIN }))
        local allowed = request(app, "POST", { origin = ORIGIN })
        tests.assertEquals(allowed.status, 201)
        tests.assertEquals(allowed.headers["Access-Control-Allow-Credentials"], "true")
        local blocked = request(app, "POST", { origin = "https://evil.example" })
        tests.assertEquals(blocked.status, 403)
        local pre = request(app, "OPTIONS", preflight(ORIGIN))
        tests.assertEquals(pre.status, 204)
        tests.assertEquals(pre.headers["Access-Control-Max-Age"], "86400")
        tests.assertEquals(request(app, "GET").status, 200, "same-origin/non-browser requests carry no Origin")
    end,

    vary_is_merged = function()
        local app = Crescent.new({ logger = function() end })
        app:use(function(ctx, next) ctx:header("Vary", "Accept-Encoding") return next() end)
        app:use(cors.create({ origins = { ORIGIN } }))
        app:get("/items", function(ctx) return ctx:text(200, "x") end)
        tests.assertEquals(request(app, "GET", { origin = ORIGIN }).headers.Vary, "Accept-Encoding, Origin")
    end,

    rejects_unsafe_configuration = function()
        tests.assertError(function() cors.create({ origins = { "https://a\r\nX: y" } }) end, "invalid CORS origin")
        tests.assertError(function() cors.create({ origins = { "*" } }) end)
        tests.assertError(function() cors.create({ max_age = -1 }) end, "max_age")
    end,
}

assert(tests.runSuite("CORS", suite))
