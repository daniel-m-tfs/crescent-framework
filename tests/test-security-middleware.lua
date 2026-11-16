package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local security_headers = require("crescent.middleware.security_headers")
local rate_limit = require("crescent.middleware.rate_limit")

local function app_with(...)
    local app = Crescent.new({ logger = function() end })
    for _, middleware in ipairs({ ... }) do app:use(middleware) end
    app:get("/", function(ctx) return ctx:text(200, "ok") end)
    app:get("/boom", function() error("boom") end)
    return app
end

local function request(app, path, remote_addr)
    local writer = { headers = {}, sent = false }
    app:handle({ method = "GET", path = path or "/", headers = {}, query = {}, remote_addr = remote_addr or "10.0.0.1" }, writer)
    return writer
end

local prefix_counter = 0
local function unique_prefix()
    prefix_counter = prefix_counter + 1
    return "test-rl-" .. prefix_counter .. ":"
end

local suite = {
    -- Security headers ----------------------------------------------------
    default_security_headers = function()
        local writer = request(app_with(security_headers.create()))
        tests.assertEquals(writer.headers["X-Content-Type-Options"], "nosniff")
        tests.assertEquals(writer.headers["X-Frame-Options"], "DENY")
        tests.assertEquals(writer.headers["Referrer-Policy"], "strict-origin-when-cross-origin")
        tests.assertNil(writer.headers["Strict-Transport-Security"], "HSTS is opt-in")
        tests.assertNil(writer.headers["Content-Security-Policy"])
    end,

    headers_are_present_on_errors = function()
        local app = app_with(security_headers.create())
        local missing = request(app, "/missing")
        tests.assertEquals(missing.status, 404)
        tests.assertEquals(missing.headers["X-Content-Type-Options"], "nosniff")
        local failed = request(app, "/boom")
        tests.assertEquals(failed.status, 500)
        tests.assertEquals(failed.headers["X-Frame-Options"], "DENY")
    end,

    headers_are_configurable = function()
        local writer = request(app_with(security_headers.create({
            frame_options = "sameorigin",
            referrer_policy = false,
            hsts = { max_age = 600, preload = true },
            csp = "default-src 'self'; frame-ancestors 'none'",
            permissions_policy = "camera=()",
            cross_origin_opener_policy = "same-origin",
            headers = { ["X-Custom"] = "1", ["X-Content-Type-Options"] = false },
        })))
        tests.assertEquals(writer.headers["X-Frame-Options"], "SAMEORIGIN")
        tests.assertNil(writer.headers["Referrer-Policy"])
        tests.assertNil(writer.headers["X-Content-Type-Options"])
        tests.assertEquals(writer.headers["Strict-Transport-Security"], "max-age=600; includeSubDomains; preload")
        tests.assertEquals(writer.headers["Content-Security-Policy"], "default-src 'self'; frame-ancestors 'none'")
        tests.assertEquals(writer.headers["Permissions-Policy"], "camera=()")
        tests.assertEquals(writer.headers["Cross-Origin-Opener-Policy"], "same-origin")
        tests.assertEquals(writer.headers["X-Custom"], "1")

        local hsts = request(app_with(security_headers.create({ hsts = true, frame_options = false })))
        tests.assertEquals(hsts.headers["Strict-Transport-Security"], "max-age=31536000; includeSubDomains")
        tests.assertNil(hsts.headers["X-Frame-Options"])
    end,

    rejects_invalid_header_configuration = function()
        tests.assertError(function() security_headers.create({ frame_options = "ALLOW-FROM x" }) end, "frame_options")
        tests.assertError(function() security_headers.create({ csp = "a\r\nSet-Cookie: x" }) end, "invalid security header")
    end,

    -- Rate limit ----------------------------------------------------------
    rate_limit_blocks_after_limit = function()
        local app = app_with(rate_limit.create({ limit = 3, window = 60, prefix = unique_prefix() }))
        for i = 1, 3 do
            local writer = request(app)
            tests.assertEquals(writer.status, 200)
            tests.assertEquals(writer.headers["X-RateLimit-Limit"], "3")
            tests.assertEquals(writer.headers["X-RateLimit-Remaining"], tostring(3 - i))
            tests.assertNotNil(tonumber(writer.headers["X-RateLimit-Reset"]))
        end
        local blocked = request(app)
        tests.assertEquals(blocked.status, 429)
        tests.assertContains(blocked.body, '"code":"rate_limited"')
        local retry = tonumber(blocked.headers["Retry-After"])
        tests.assertTrue(retry >= 1 and retry <= 60, "Retry-After within the window")
        tests.assertEquals(blocked.headers["X-RateLimit-Remaining"], "0")
    end,

    rate_limit_keys_by_remote_addr = function()
        local app = app_with(rate_limit.create({ limit = 1, window = 60, prefix = unique_prefix() }))
        tests.assertEquals(request(app, "/", "10.0.0.1").status, 200)
        tests.assertEquals(request(app, "/", "10.0.0.1").status, 429)
        tests.assertEquals(request(app, "/", "10.0.0.2").status, 200)
    end,

    rate_limit_ignores_forwarded_headers = function()
        local app = app_with(rate_limit.create({ limit = 1, window = 60, prefix = unique_prefix() }))
        local function spoofed(ip)
            local writer = { headers = {}, sent = false }
            app:handle({ method = "GET", path = "/", query = {}, remote_addr = "10.9.9.9",
                headers = { ["x-forwarded-for"] = ip, ["x-real-ip"] = ip } }, writer)
            return writer
        end
        tests.assertEquals(spoofed("1.1.1.1").status, 200)
        tests.assertEquals(spoofed("2.2.2.2").status, 429, "a forged X-Forwarded-For must not reset the bucket")
    end,

    rate_limit_custom_key = function()
        local app = app_with(rate_limit.create({
            limit = 1, window = 60, prefix = unique_prefix(),
            key = function(ctx) if ctx.remote_addr ~= "127.0.0.1" then return "global" end end,
        }))
        tests.assertEquals(request(app, "/", "10.0.0.1").status, 200)
        tests.assertEquals(request(app, "/", "10.0.0.2").status, 429, "shared key")
        tests.assertEquals(request(app, "/", "127.0.0.1").status, 200, "nil key is not limited")
        tests.assertEquals(request(app, "/", "127.0.0.1").status, 200)
    end,

    rate_limit_state_is_shared_between_instances = function()
        -- Two limiters with the same prefix model two workers: the count
        -- lives in ngx.shared, not in either instance.
        local prefix = unique_prefix()
        local worker_a = app_with(rate_limit.create({ limit = 2, window = 60, prefix = prefix }))
        local worker_b = app_with(rate_limit.create({ limit = 2, window = 60, prefix = prefix }))
        tests.assertEquals(request(worker_a).status, 200)
        tests.assertEquals(request(worker_b).status, 200)
        tests.assertEquals(request(worker_a).status, 429)
    end,

    rate_limit_requires_shared_dict = function()
        tests.assertError(function() rate_limit.create({ dict = "missing_dict" }) end, "lua_shared_dict missing_dict")
        tests.assertError(function() rate_limit.create({ limit = 0 }) end, "limit")
        tests.assertError(function() rate_limit.create({ window = 0 }) end, "window")
    end,
}

assert(tests.runSuite("Security middleware", suite))
