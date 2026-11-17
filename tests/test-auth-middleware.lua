package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local auth = require("crescent.middleware.auth")
local jwt = require("crescent.security.jwt")
local Base64 = require("crescent.security.base64")

local SECRET = "test_secret_key_super_secure_123456"

local function app_with(middleware)
    local app = Crescent.new({ logger = function() end })
    if middleware then app:use(middleware) end
    app:get("/me", function(ctx)
        return ctx:json(200, { user = ctx.state.user or false, has_jwt = ctx.state.jwt ~= nil })
    end)
    return app
end

local function request(app, path, headers, method)
    local writer = { headers = {}, sent = false }
    app:handle({ method = method or "GET", path = path or "/me", headers = headers or {}, query = {} }, writer)
    return writer
end

local function bearer(token) return { authorization = "Bearer " .. token } end
local function basic(credentials) return { authorization = "Basic " .. Base64.encode(credentials) } end

local suite = {
    -- Bearer ------------------------------------------------------------
    bearer_accepts_valid_token = function()
        local seen
        local app = app_with(auth.bearer(function(token, ctx)
            seen = token
            tests.assertNotNil(ctx.state)
            if token == "good" then return true, { id = 1 } end
            return false
        end))
        local ok = request(app, "/me", bearer("good"))
        tests.assertEquals(ok.status, 200)
        tests.assertContains(ok.body, '"id":1')
        tests.assertEquals(seen, "good")

        local bad = request(app, "/me", bearer("bad"))
        tests.assertEquals(bad.status, 401)
        tests.assertContains(bad.body, '"code":"invalid_credentials"')
        tests.assertEquals(bad.headers["WWW-Authenticate"], 'Bearer error="invalid_token"')

        local missing = request(app, "/me")
        tests.assertEquals(missing.status, 401)
        tests.assertContains(missing.body, '"code":"missing_credentials"')
        tests.assertEquals(missing.headers["WWW-Authenticate"], "Bearer")
    end,

    oversized_credentials_are_rejected = function()
        local called = false
        local app = app_with(auth.bearer(function() called = true return true, {} end))
        local writer = request(app, "/me", bearer(string.rep("a", 9000)))
        tests.assertEquals(writer.status, 401)
        tests.assertContains(writer.body, '"code":"credentials_too_large"')
        tests.assertFalse(called)

        local key_app = app_with(auth.api_key(function() called = true return true, {} end))
        tests.assertEquals(request(key_app, "/me", { ["x-api-key"] = string.rep("k", 9000) }).status, 401)
        tests.assertFalse(called)
    end,

    validators_must_be_functions = function()
        tests.assertError(function() auth.bearer(nil) end, "validator must be a function")
        tests.assertError(function() auth.basic("x") end, "validator must be a function")
        tests.assertError(function() auth.api_key("x-key", nil) end, "validator must be a function")
        tests.assertError(function() auth.basic(function() end, { realm = 'a"b' }) end, "realm")
    end,

    -- Basic (ported from the original tests/test-security.lua) ------------
    basic_decodes_real_credentials = function()
        local user, pass
        local app = app_with(auth.basic(function(u, p)
            user, pass = u, p
            return true, { username = u }
        end))
        local writer = request(app, "/me", basic("admin:s3cr3t!"))
        tests.assertEquals(writer.status, 200)
        tests.assertEquals(user, "admin")
        tests.assertEquals(pass, "s3cr3t!")
    end,

    basic_password_may_contain_colon = function()
        local pass
        local app = app_with(auth.basic(function(_, p) pass = p return true, {} end))
        tests.assertEquals(request(app, "/me", basic("admin:a:b:c")).status, 200)
        tests.assertEquals(pass, "a:b:c")
    end,

    basic_rejects_malformed_input = function()
        local called = false
        local app = app_with(auth.basic(function() called = true return true, {} end, { realm = "Admin" }))
        local cases = {
            { authorization = "Basic %%%not-base64%%%" },
            { authorization = "Basic " .. Base64.encode("no-colon") },
            { authorization = "Basic " .. Base64.encode(":password") },
            { authorization = "Bearer abc" },
            { authorization = "Basic" },
        }
        for _, headers in ipairs(cases) do
            local writer = request(app, "/me", headers)
            tests.assertEquals(writer.status, 401, headers.authorization)
            tests.assertContains(writer.body, '"code":"invalid_credentials"')
            tests.assertEquals(writer.headers["WWW-Authenticate"], 'Basic realm="Admin", charset="UTF-8"')
        end
        tests.assertFalse(called, "validator must not run for malformed credentials")
        local missing = request(app, "/me")
        tests.assertEquals(missing.status, 401)
        tests.assertContains(missing.body, '"code":"missing_credentials"')
    end,

    basic_rejects_wrong_credentials = function()
        local app = app_with(auth.basic(function(u, p)
            return auth.secure_compare(u, "admin") and auth.secure_compare(p, "pw"), { username = u }
        end))
        tests.assertEquals(request(app, "/me", basic("admin:pw")).status, 200)
        tests.assertEquals(request(app, "/me", basic("admin:nope")).status, 401)
    end,

    -- API key -----------------------------------------------------------
    api_key_header = function()
        local validator = function(key) return key == "k1", { name = "svc" } end
        local default_app = app_with(auth.api_key(validator))
        tests.assertEquals(request(default_app, "/me", { ["x-api-key"] = "k1" }).status, 200)
        tests.assertEquals(request(default_app, "/me", { ["x-api-key"] = "k2" }).status, 401)
        tests.assertEquals(request(default_app, "/me", { ["x-api-key"] = "" }).status, 401)

        local custom = app_with(auth.api_key("X-Service-Key", validator))
        local writer = request(custom, "/me", { ["x-service-key"] = "k1" })
        tests.assertEquals(writer.status, 200)
        tests.assertContains(writer.body, '"name":"svc"')
    end,

    rejected_validator_tables_do_not_leak = function()
        local app = app_with(auth.api_key(function() return false, { secret_row = "internal" } end))
        local writer = request(app, "/me", { ["x-api-key"] = "k" })
        tests.assertEquals(writer.status, 401)
        tests.assertNotContains(writer.body, "secret_row")
        tests.assertContains(writer.body, "invalid api key")
        local custom = app_with(auth.bearer(function() return false, "token revoked" end))
        tests.assertContains(request(custom, "/me", bearer("t")).body, "token revoked")
    end,

    -- JWT ---------------------------------------------------------------
    jwt_sets_user_and_payload = function()
        local app = app_with(auth.jwt({ secret = SECRET }))
        local token = auth.generate_access_token({ user_id = 5 }, { secret = SECRET })
        local writer = request(app, "/me", bearer(token))
        tests.assertEquals(writer.status, 200)
        tests.assertContains(writer.body, '"user_id":5')
        tests.assertContains(writer.body, '"has_jwt":true')
    end,

    jwt_get_user = function()
        local app = app_with(auth.jwt({
            secret = SECRET,
            get_user = function(payload) if payload.user_id == 1 then return { name = "Ana" } end end,
        }))
        local ok = request(app, "/me", bearer(jwt.sign({ user_id = 1 }, SECRET)))
        tests.assertEquals(ok.status, 200)
        tests.assertContains(ok.body, '"name":"Ana"')
        local unknown = request(app, "/me", bearer(jwt.sign({ user_id = 2 }, SECRET)))
        tests.assertEquals(unknown.status, 401)
        tests.assertContains(unknown.body, '"code":"invalid_token"')
    end,

    jwt_failures = function()
        local app = app_with(auth.jwt({ secret = SECRET, issuer = "crescent" }))
        local missing = request(app, "/me")
        tests.assertEquals(missing.status, 401)
        tests.assertContains(missing.body, '"code":"missing_credentials"')

        local wrong_secret = request(app, "/me", bearer(jwt.sign({}, "other", { issuer = "crescent" })))
        tests.assertEquals(wrong_secret.status, 401)
        tests.assertContains(wrong_secret.body, '"code":"invalid_token"')
        tests.assertEquals(wrong_secret.headers["WWW-Authenticate"], 'Bearer error="invalid_token"')

        local wrong_issuer = request(app, "/me", bearer(jwt.sign({}, SECRET, { issuer = "evil" })))
        tests.assertEquals(wrong_issuer.status, 401)

        local expired = request(app, "/me", bearer(jwt.sign({ exp = ngx.time() - 5 }, SECRET, { issuer = "crescent" })))
        tests.assertEquals(expired.status, 401)
        tests.assertContains(expired.body, '"code":"token_expired"')
    end,

    jwt_rejects_refresh_tokens = function()
        local app = app_with(auth.jwt({ secret = SECRET }))
        local pair = auth.generate_token_pair({ id = 9 }, { secret = SECRET })
        tests.assertEquals(request(app, "/me", bearer(pair.access_token)).status, 200)
        local refresh = request(app, "/me", bearer(pair.refresh_token))
        tests.assertEquals(refresh.status, 401)
        tests.assertContains(refresh.body, '"code":"invalid_token"')
    end,

    jwt_rejects_alg_confusion = function()
        local app = app_with(auth.jwt({ secret = SECRET }))
        local hs512 = jwt.sign({ user_id = 1 }, SECRET, { algorithm = "HS512" })
        tests.assertEquals(request(app, "/me", bearer(hs512)).status, 401)
        local allow_512 = app_with(auth.jwt({ secret = SECRET, algorithms = { "HS512" } }))
        tests.assertEquals(request(allow_512, "/me", bearer(hs512)).status, 200)
        tests.assertError(function() auth.jwt({ secret = SECRET, algorithms = { "none" } }) end, "unsupported JWT algorithm")
        tests.assertError(function() auth.jwt({ secret = SECRET, algorithms = { "RS256" } }) end, "unsupported JWT algorithm")
    end,

    jwt_revoked_token = function()
        local app = app_with(auth.jwt({ secret = SECRET }))
        local token = auth.generate_access_token({ user_id = 3 }, { secret = SECRET })
        tests.assertEquals(request(app, "/me", bearer(token)).status, 200)
        local _, payload = auth.verify_token(token, { secret = SECRET })
        auth.revoke_token(payload)
        local writer = request(app, "/me", bearer(token))
        tests.assertEquals(writer.status, 401)
        tests.assertContains(writer.body, '"code":"token_revoked"')
        jwt.unrevoke(payload.jti)
    end,

    jwt_requires_secret = function()
        tests.assertError(function() auth.jwt({ secret = "" }) end, "JWT secret is required")
        tests.assertError(function() auth.jwt({ secret = "short-secret" }) end, "at least 32 bytes")
        tests.assertNoError(function() auth.jwt({ secret = "short-secret", allow_weak_secret = true }) end)
        if not require("crescent.env").get("JWT_SECRET") then
            tests.assertError(function() auth.jwt() end, "JWT secret is required")
            tests.assertError(function() auth.generate_token_pair(1) end, "JWT secret is required")
        end
    end,

    optional_authentication = function()
        local app = app_with(auth.jwt({ secret = SECRET, optional = true }))
        local anonymous = request(app, "/me")
        tests.assertEquals(anonymous.status, 200)
        tests.assertContains(anonymous.body, '"has_jwt":false')
        local invalid = request(app, "/me", bearer("garbage"))
        tests.assertEquals(invalid.status, 200)
        tests.assertContains(invalid.body, '"has_jwt":false')
        local valid = request(app, "/me", bearer(jwt.sign({ user_id = 4 }, SECRET)))
        tests.assertContains(valid.body, '"user_id":4')

        local basic_app = app_with(auth.basic(function() return false end, { optional = true }))
        local writer = request(basic_app, "/me", basic("a:b"))
        tests.assertEquals(writer.status, 200)
        tests.assertNil(writer.headers["WWW-Authenticate"])
    end,

    protect_wraps_a_single_route = function()
        local app = Crescent.new({ logger = function() end })
        app:get("/public", function(ctx) return ctx:text(200, "public") end)
        app:get("/me", auth.protect(auth.jwt({ secret = SECRET }), function(ctx)
            return ctx:json(200, { id = ctx.state.user.user_id })
        end))
        local tagged = function(ctx, next) ctx.state.tag = "x" return next() end
        app:get("/chain", auth.protect({ tagged, auth.jwt({ secret = SECRET }) }, function(ctx)
            return ctx:text(200, ctx.state.tag)
        end))

        tests.assertEquals(request(app, "/public").status, 200)
        tests.assertEquals(request(app, "/me").status, 401)
        local token = jwt.sign({ user_id = 11 }, SECRET)
        local writer = request(app, "/me", bearer(token))
        tests.assertEquals(writer.status, 200)
        tests.assertContains(writer.body, '"id":11')
        tests.assertEquals(request(app, "/chain", bearer(token)).body, "x")
        tests.assertEquals(request(app, "/chain").status, 401)
        tests.assertError(function() auth.protect(auth.jwt({ secret = SECRET })) end, "protect requires an action")
    end,

    blocked_request_does_not_reach_action = function()
        local reached = false
        local app = Crescent.new({ logger = function() end })
        app:use(auth.jwt({ secret = SECRET }))
        app:get("/x", function(ctx) reached = true return ctx:text(200, "x") end)
        tests.assertEquals(request(app, "/x").status, 401)
        tests.assertFalse(reached)
    end,

    -- Token helpers (ported from the original tests/test-auth.lua) -------
    generate_token = function()
        local token = auth.generate_token({ user_id = 1, username = "testuser" }, { secret = SECRET, expires_in = 3600 })
        local ok, decoded = jwt.verify(token, SECRET)
        tests.assertTrue(ok)
        tests.assertEquals(decoded.user_id, 1)
        tests.assertEquals(decoded.exp - decoded.iat, 3600)
    end,

    generate_token_pair = function()
        for _, user in ipairs({ { user_id = 1, username = "testuser" }, { id = 1 }, 1 }) do
            local pair = auth.generate_token_pair(user, { secret = SECRET, issuer = "crescent" })
            tests.assertEquals(pair.token_type, "Bearer")
            tests.assertEquals(pair.expires_in, 15 * 60)
            local ok_access, access = jwt.verify(pair.access_token, SECRET, { issuer = "crescent" })
            local ok_refresh, refresh = auth.verify_refresh_token(pair.refresh_token, { secret = SECRET, issuer = "crescent" })
            tests.assertTrue(ok_access)
            tests.assertTrue(ok_refresh)
            tests.assertEquals(access.user_id, 1)
            tests.assertEquals(refresh.user_id, 1)
            tests.assertEquals(refresh.typ, "refresh")
            tests.assertFalse(auth.verify_refresh_token(pair.access_token, { secret = SECRET }))
        end
        tests.assertError(function() auth.generate_token_pair({ name = "x" }, { secret = SECRET }) end, "user has no id")
    end,

    verify_and_decode_helpers = function()
        local token = jwt.sign({ user_id = 1, username = "testuser" }, SECRET)
        local ok, decoded = auth.verify_token(token, { secret = SECRET })
        tests.assertTrue(ok)
        tests.assertEquals(decoded.user_id, 1)
        tests.assertFalse(auth.verify_token(token, { secret = "wrong_secret_wrong_secret_wrong_secret" }))
        local header, payload = auth.decode_token(token)
        tests.assertEquals(header.alg, "HS256")
        tests.assertEquals(payload.username, "testuser")
    end,
}

assert(tests.runSuite("Auth middleware", suite))
