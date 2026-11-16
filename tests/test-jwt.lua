package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local jwt = require("crescent.security.jwt")
local Base64 = require("crescent.security.base64")
local Crypto = require("crescent.security.crypto")
local json = require("crescent.json")

local SECRET = "test_secret_key_super_secure_123456"

local function forge(header, payload, secret, digest)
    local message = Base64.url_encode(json.encode(header)) .. "." .. Base64.url_encode(json.encode(payload))
    local signature = secret and Base64.url_encode(Crypto.hmac(digest or "sha256", secret, message)) or ""
    return message .. "." .. signature
end

local suite = {
    -- Regression tests ported from the original tests/test-auth.lua -----
    sign_and_verify = function()
        local token = jwt.sign({ user_id = 1, username = "testuser", email = "test@example.com" }, SECRET)
        tests.assertIsString(token)
        local ok, decoded = jwt.verify(token, SECRET)
        tests.assertTrue(ok)
        tests.assertEquals(decoded.user_id, 1)
        tests.assertEquals(decoded.username, "testuser")
        tests.assertEquals(decoded.email, "test@example.com")
    end,

    expiration_claim = function()
        local ok, decoded = jwt.verify(jwt.sign({ user_id = 1 }, SECRET, { expires_in = 1 }), SECRET)
        tests.assertTrue(ok)
        tests.assertNotNil(decoded.exp)
    end,

    invalid_signature = function()
        local ok, message, code = jwt.verify(jwt.sign({ user_id = 1 }, SECRET), "wrong_secret")
        tests.assertFalse(ok)
        tests.assertEquals(message, "invalid signature")
        tests.assertEquals(code, "invalid_signature")
    end,

    invalid_formats = function()
        for _, token in ipairs({ "invalid.token", "invalid", "", "a.b.c.d", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", "a..c" }) do
            tests.assertFalse(jwt.verify(token, SECRET), "must reject " .. token)
        end
        tests.assertFalse(jwt.verify(nil, SECRET))
        tests.assertFalse(jwt.verify(jwt.sign({}, SECRET), ""))
    end,

    decode_without_verification = function()
        local header, payload = jwt.decode(jwt.sign({ user_id = 1, username = "testuser" }, SECRET))
        tests.assertEquals(header.alg, "HS256")
        tests.assertEquals(header.typ, "JWT")
        tests.assertEquals(payload.user_id, 1)
        tests.assertEquals(payload.username, "testuser")
        tests.assertNil(jwt.decode("garbage"))
    end,

    issuer = function()
        local token = jwt.sign({ user_id = 1 }, SECRET, { issuer = "crescent-app" })
        local ok, decoded = jwt.verify(token, SECRET, { issuer = "crescent-app" })
        tests.assertTrue(ok)
        tests.assertEquals(decoded.iss, "crescent-app")
        local bad, _, code = jwt.verify(token, SECRET, { issuer = "wrong-issuer" })
        tests.assertFalse(bad)
        tests.assertEquals(code, "invalid_issuer")
    end,

    audience_string_and_list = function()
        local token = jwt.sign({ user_id = 1 }, SECRET, { audience = "api-users" })
        tests.assertTrue(jwt.verify(token, SECRET, { audience = "api-users" }))
        tests.assertTrue(jwt.verify(token, SECRET, { audience = { "other", "api-users" } }))
        tests.assertFalse(jwt.verify(token, SECRET, { audience = "wrong-audience" }))
        local multi = jwt.sign({ user_id = 1 }, SECRET, { audience = { "web", "mobile" } })
        tests.assertTrue(jwt.verify(multi, SECRET, { audience = "mobile" }))
        tests.assertFalse(jwt.verify(multi, SECRET, { audience = "admin" }))
        tests.assertFalse(jwt.verify(jwt.sign({}, SECRET), SECRET, { audience = "web" }), "missing aud must fail")
    end,

    not_before = function()
        local ok, message, code = jwt.verify(jwt.sign({ user_id = 1 }, SECRET, { not_before = 2 }), SECRET)
        tests.assertFalse(ok)
        tests.assertContains(message, "not yet valid")
        tests.assertEquals(code, "token_not_yet_valid")
    end,

    issued_at_and_jti = function()
        local ok, decoded = jwt.verify(jwt.sign({ user_id = 1 }, SECRET), SECRET)
        tests.assertTrue(ok)
        tests.assertType(decoded.iat, "number")
        tests.assertMatches(decoded.jti, "^%x+$")
        tests.assertEquals(#decoded.jti, 32)
        local _, other = jwt.decode(jwt.sign({ user_id = 1 }, SECRET))
        tests.assertNotEquals(other.jti, decoded.jti)
        local _, no_jti = jwt.decode(jwt.sign({}, SECRET, { jti = false }))
        tests.assertNil(no_jti.jti)
    end,

    access_and_refresh_tokens = function()
        local access = jwt.create_access_token({ user_id = 1 }, SECRET)
        local ok, decoded = jwt.verify(access, SECRET)
        tests.assertTrue(ok)
        tests.assertEquals(decoded.typ, "access")
        tests.assertEquals(decoded.exp - decoded.iat, 15 * 60)

        local refresh = jwt.create_refresh_token({ user_id = 1 }, SECRET)
        local refresh_ok, refresh_payload = jwt.verify(refresh, SECRET)
        tests.assertTrue(refresh_ok)
        tests.assertEquals(refresh_payload.typ, "refresh")
        tests.assertEquals(refresh_payload.exp - refresh_payload.iat, 30 * 24 * 60 * 60)
    end,

    custom_access_expiry = function()
        local _, decoded = jwt.verify(jwt.create_access_token({ user_id = 1 }, SECRET, 3600), SECRET)
        tests.assertEquals(decoded.exp - decoded.iat, 3600)
    end,

    token_type_enforcement = function()
        local access = jwt.create_access_token({ user_id = 1 }, SECRET)
        local refresh = jwt.create_refresh_token({ user_id = 1 }, SECRET)
        local ok, _, code = jwt.verify(refresh, SECRET, { token_type = "access" })
        tests.assertFalse(ok)
        tests.assertEquals(code, "invalid_token_type")
        tests.assertTrue(jwt.verify(access, SECRET, { token_type = "access" }))
        tests.assertTrue(jwt.verify(jwt.sign({}, SECRET), SECRET, { token_type = "access" }), "untyped token counts as access")
        tests.assertTrue(jwt.verify(refresh, SECRET, { token_type = "refresh" }))
        tests.assertFalse(jwt.verify(access, SECRET, { token_type = "refresh" }))
        local forged_type = jwt.create_access_token({ user_id = 1, typ = "refresh" }, SECRET)
        local _, payload = jwt.decode(forged_type)
        tests.assertEquals(payload.typ, "access", "create_access_token must not keep a caller-supplied typ")
    end,

    complex_and_unicode_payloads = function()
        local payload = {
            user_id = 1,
            roles = { "admin", "user" },
            permissions = { read = true, delete = false },
            metadata = { created_at = 1234567890, last_login = 9876543210 },
            name = "José da Silva",
            message = "Olá! 你好 🚀",
            description = string.rep("a", 10000),
        }
        local ok, decoded = jwt.verify(jwt.sign(payload, SECRET), SECRET)
        tests.assertTrue(ok)
        tests.assertEquals(#decoded.roles, 2)
        tests.assertEquals(decoded.roles[1], "admin")
        tests.assertTrue(decoded.permissions.read)
        tests.assertFalse(decoded.permissions.delete)
        tests.assertEquals(decoded.metadata.last_login, 9876543210)
        tests.assertEquals(decoded.name, "José da Silva")
        tests.assertEquals(decoded.message, "Olá! 你好 🚀")
        tests.assertEquals(#decoded.description, 10000)
    end,

    empty_payload = function()
        local ok, decoded = jwt.verify(jwt.sign({}, SECRET), SECRET)
        tests.assertTrue(ok)
        tests.assertNotNil(decoded.iat)
    end,

    special_characters_in_secret = function()
        local special = "my@secret#key$with%special^chars&123*()_+-=[]{}|;:',.<>?/"
        local token = jwt.sign({ user_id = 1 }, special)
        tests.assertTrue(jwt.verify(token, special))
        tests.assertFalse(jwt.verify(token, SECRET))
    end,

    sign_argument_errors = function()
        tests.assertError(function() jwt.sign({ user_id = 1 }, "") end, "secret is required")
        tests.assertError(function() jwt.sign("not a table", SECRET) end, "payload must be a table")
        tests.assertError(function() jwt.sign({}, SECRET, { algorithm = "none" }) end, "unsupported algorithm")
    end,

    independent_tokens = function()
        local t1, t2 = jwt.sign({ user_id = 1 }, SECRET), jwt.sign({ user_id = 2 }, SECRET)
        tests.assertNotEquals(t1, t2)
        local _, d1 = jwt.verify(t1, SECRET)
        local _, d2 = jwt.verify(t2, SECRET)
        tests.assertEquals(d1.user_id, 1)
        tests.assertEquals(d2.user_id, 2)
    end,

    -- Ported from the original tests/test-core.lua ----------------------
    claim_types_are_checked = function()
        for claim, message in pairs({ exp = "invalid expiration claim", nbf = "invalid not-before claim", iat = "invalid issued-at claim" }) do
            local ok, err = jwt.verify(jwt.sign({ [claim] = "not-a-number" }, "secret"), "secret")
            tests.assertFalse(ok)
            tests.assertEquals(err, message)
        end
    end,

    -- New --------------------------------------------------------------
    known_vector_from_rfc_tooling = function()
        -- Reference HS256 token published by jwt.io (secret "your-256-bit-secret").
        local token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
            .. "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ."
            .. "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        local ok, payload = jwt.verify(token, "your-256-bit-secret")
        tests.assertTrue(ok)
        tests.assertEquals(payload.name, "John Doe")
        tests.assertFalse(jwt.verify(token:sub(1, -2) .. "d", "your-256-bit-secret"), "non-canonical signature")
    end,

    expired_and_leeway = function()
        local fixed = function() return 1000 end
        local token = jwt.sign({ exp = 990 }, SECRET)
        local ok, _, code = jwt.verify(token, SECRET, { now = fixed })
        tests.assertFalse(ok)
        tests.assertEquals(code, "token_expired")
        tests.assertTrue(jwt.verify(token, SECRET, { now = fixed, leeway = 30 }))
        tests.assertFalse(jwt.verify(token, SECRET, { now = fixed, leeway = -1 }))
        tests.assertFalse(jwt.verify(token, SECRET, { now = fixed, leeway = 0 / 0 }))
        tests.assertFalse(jwt.verify(jwt.sign({}, SECRET), SECRET, { require_exp = true }))
    end,

    alg_none_is_rejected = function()
        local token = forge({ alg = "none", typ = "JWT" }, { user_id = 1, admin = true })
        tests.assertFalse(jwt.verify(token, SECRET), "unsigned token (empty signature)")
        local ok, _, code = jwt.verify(token .. "x", SECRET)
        tests.assertFalse(ok)
        tests.assertEquals(code, "unsupported_algorithm")
        tests.assertFalse(jwt.verify(token, SECRET, { algorithms = { "none" } }), "none can never be enabled")
        tests.assertFalse(jwt.verify(forge({ alg = "NONE" }, {}, SECRET), SECRET))
    end,

    alg_confusion_is_rejected = function()
        -- An attacker who signs with HS512 (or claims RS256) must not be
        -- accepted by a verifier pinned to HS256.
        local hs512 = forge({ alg = "HS512", typ = "JWT" }, { user_id = 1 }, SECRET, "sha512")
        tests.assertFalse(jwt.verify(hs512, SECRET))
        tests.assertTrue(jwt.verify(hs512, SECRET, { algorithms = { "HS512" } }))
        local rs256 = forge({ alg = "RS256", typ = "JWT" }, { user_id = 1 }, SECRET)
        tests.assertFalse(jwt.verify(rs256, SECRET, { algorithms = { "HS256", "RS256" } }))
        local mismatch = forge({ alg = "HS384" }, { user_id = 1 }, SECRET, "sha256")
        tests.assertFalse(jwt.verify(mismatch, SECRET, { algorithms = { "HS384" } }))
        tests.assertFalse(jwt.verify(forge({ alg = { "HS256" } }, {}, SECRET), SECRET))
    end,

    hs384_and_hs512 = function()
        for _, alg in ipairs({ "HS384", "HS512" }) do
            local token = jwt.sign({ user_id = 7 }, SECRET, { algorithm = alg })
            local header = jwt.decode(token)
            tests.assertEquals(header.alg, alg)
            local ok, payload = jwt.verify(token, SECRET, { algorithms = { alg } })
            tests.assertTrue(ok)
            tests.assertEquals(payload.user_id, 7)
        end
    end,

    tampered_payload = function()
        local token = jwt.sign({ user_id = 1, admin = false }, SECRET)
        local header_part, _, signature = token:match("^([^.]+)%.([^.]+)%.([^.]+)$")
        local tampered = header_part .. "." .. Base64.url_encode(json.encode({ user_id = 1, admin = true })) .. "." .. signature
        tests.assertFalse(jwt.verify(tampered, SECRET))
    end,

    revocation_uses_shared_dict = function()
        local token = jwt.sign({ jti = "test-jti" }, "secret", { expires_in = 60 })
        jwt.revoke("test-jti", ngx.time() + 60)
        local ok, err, code = jwt.verify(token, "secret")
        tests.assertFalse(ok)
        tests.assertEquals(err, "token revoked")
        tests.assertEquals(code, "token_revoked")
        local ttl = ngx.shared.crescent_jwt:ttl("jwt:revoked:test-jti")
        tests.assertTrue(ttl > 0 and ttl <= 60, "revocation entry expires with the token")
        jwt.unrevoke("test-jti")
        tests.assertTrue(jwt.verify(token, "secret"))
    end,

    revocation_is_visible_across_workers = function()
        -- A worker is a separate Lua VM: simulate one by loading a fresh copy
        -- of the module. Only state in ngx.shared is visible to both.
        local token = jwt.sign({ user_id = 1 }, SECRET, { expires_in = 60 })
        local _, payload = jwt.decode(token)
        jwt.revoke(payload)
        package.loaded["crescent.security.jwt"] = nil
        local other_worker = require("crescent.security.jwt")
        package.loaded["crescent.security.jwt"] = jwt
        tests.assertTrue(other_worker ~= jwt)
        local ok, _, code = other_worker.verify(token, SECRET)
        tests.assertFalse(ok)
        tests.assertEquals(code, "token_revoked")
        other_worker.unrevoke(payload.jti)
        tests.assertTrue(jwt.verify(token, SECRET))
    end,

    revocation_of_expired_token_is_noop = function()
        tests.assertTrue(jwt.revoke("old-jti", ngx.time() - 10))
        tests.assertNil(ngx.shared.crescent_limits:get("jwt:revoked:old-jti"))
    end,

    pluggable_revocation_store = function()
        local revoked = {}
        local store = {
            revoke = function(jti) revoked[jti] = true end,
            is_revoked = function(jti) return revoked[jti] == true end,
        }
        local token = jwt.sign({ jti = "custom" }, SECRET)
        jwt.revoke("custom", nil, store)
        tests.assertFalse(jwt.verify(token, SECRET, { revocation = store }))
        tests.assertTrue(jwt.verify(token, SECRET), "default store is untouched")
        tests.assertTrue(jwt.verify(token, SECRET, { revocation = false }))
        tests.assertError(function() jwt.set_revocation_store({}) end)
    end,

    invalid_jti_type = function()
        local ok, _, code = jwt.verify(jwt.sign({ jti = 123 }, SECRET), SECRET)
        tests.assertFalse(ok)
        tests.assertEquals(code, "invalid_claim")
    end,

    base64_strictness = function()
        tests.assertEquals(Base64.decode(Base64.encode("admin:s3cr3t!")), "admin:s3cr3t!")
        tests.assertEquals(Base64.decode(""), "")
        tests.assertNil(Base64.decode("not-valid-base64!!"))
        tests.assertNil(Base64.decode("=AAA"))
        tests.assertNil(Base64.decode("A=AA"))
        tests.assertNil(Base64.decode("AA=A"))
        tests.assertNil(Base64.decode("AA"))
        tests.assertNotNil(Base64.decode("AA=="))
        tests.assertNotNil(Base64.decode("AAA="))
        tests.assertEquals(Base64.url_decode(Base64.url_encode("\255\254\253")), "\255\254\253")
        tests.assertNil(Base64.url_decode("ab+/"))
        tests.assertNil(Base64.url_decode("abcde"))
    end,
}

assert(tests.runSuite("JWT", suite))
