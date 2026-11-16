package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local password = require("crescent.security.password")

-- Low iteration count keeps the suite fast; the default is exercised once.
local FAST = 1000

local function parts(stored)
    local result = {}
    for part in stored:gmatch("[^$]+") do result[#result + 1] = part end
    return result
end

local suite = {
    -- Ported from the original tests/test-hash.lua -----------------------
    same_password_different_salts = function()
        tests.assertNotEquals(password.hash("password123", FAST), password.hash("password123", FAST))
    end,

    verify_correct_and_incorrect = function()
        local stored = password.hash("mySecretPass123", FAST)
        tests.assertTrue(password.verify("mySecretPass123", stored))
        tests.assertFalse(password.verify("wrongPassword", stored))
    end,

    hash_format = function()
        local fields = parts(password.hash("test123", FAST))
        tests.assertEquals(#fields, 3)
        tests.assertEquals(tonumber(fields[1]), FAST)
        tests.assertMatches(fields[2], "^%x+$")
        tests.assertEquals(#fields[2], 32, "16-byte salt")
        tests.assertEquals(#fields[3], 64, "32-byte key")
    end,

    custom_iterations = function()
        tests.assertMatches(password.hash("test123", 5000), "^5000%$")
    end,

    default_iterations = function()
        local stored = password.hash("test123")
        tests.assertEquals(tonumber(parts(stored)[1]), password.DEFAULT_ITERATIONS)
        tests.assertTrue(password.verify("test123", stored))
    end,

    secure_compare = function()
        tests.assertTrue(password.secure_compare("same_string", "same_string"))
        tests.assertFalse(password.secure_compare("same_string", "different"))
        tests.assertFalse(password.secure_compare("abc", "abcd"))
        tests.assertFalse(password.secure_compare("abc", nil))
    end,

    empty_password = function()
        tests.assertError(function() password.hash("") end, "password must be a non-empty string")
        tests.assertError(function() password.hash(nil) end, "password must be a non-empty string")
        tests.assertFalse(password.verify("", password.hash("x", FAST)))
    end,

    invalid_iterations = function()
        tests.assertError(function() password.hash("x", 0) end, "iterations")
        tests.assertError(function() password.hash("x", 1.5) end, "iterations")
        tests.assertError(function() password.hash("x", password.MAX_ITERATIONS + 1) end, "iterations")
    end,

    -- Ported from the original tests/test-core.lua -----------------------
    malformed_hashes_return_false = function()
        local valid = password.hash("password", FAST)
        local malformed = {
            "999999999$zz$zz",
            "", "not a hash", "1000$abc", "1000$$",
            "0$000102030405060708090a0b0c0d0e0f$" .. string.rep("00", 32),
            "1000$0001$" .. string.rep("00", 32),
            "1000$000102030405060708090a0b0c0d0e0f$" .. string.rep("00", 31),
            "1000$000102030405060708090a0b0c0d0e0g$" .. string.rep("00", 32),
            valid .. "$extra",
            " " .. valid,
        }
        for _, stored in ipairs(malformed) do
            tests.assertFalse(password.verify("password", stored), "must reject " .. stored)
        end
        tests.assertFalse(password.verify("password", nil))
        tests.assertFalse(password.verify("password", {}))
        tests.assertFalse(password.verify(nil, valid))
    end,

    -- New ---------------------------------------------------------------
    verifies_hashes_from_the_original_framework = function()
        -- Expected keys computed independently with Python:
        --   hashlib.pbkdf2_hmac("sha256", password, bytes(range(16)), iterations).hex()
        local salt = "000102030405060708090a0b0c0d0e0f"
        local legacy_default = "100000$" .. salt .. "$49d49c25f597846209f0d92e7770ab64e1c75e94b4ce6c509265ee67175d2a1e"
        tests.assertTrue(password.verify("correct horse battery staple", legacy_default))
        tests.assertFalse(password.verify("correct horse battery stapl", legacy_default))

        local with_colon = "10000$" .. salt .. "$356116fb4e09675b5347b6768c083b7bf9bb0a6895eb483f70fbd53595924ce2"
        tests.assertTrue(password.verify("p@ss:wörd", with_colon))
        tests.assertTrue(password.verify("p@ss:wörd", with_colon:upper()), "uppercase hex is accepted")
    end,

    needs_rehash = function()
        local weak = password.hash("x", FAST)
        tests.assertTrue(password.needs_rehash(weak))
        tests.assertTrue(password.needs_rehash(weak, FAST + 1))
        tests.assertFalse(password.needs_rehash(weak, FAST))
        tests.assertTrue(password.needs_rehash("garbage"))
        tests.assertTrue(password.needs_rehash(nil))
    end,
}

assert(tests.runSuite("Password", suite))
