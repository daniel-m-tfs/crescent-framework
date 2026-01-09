local tests = require('../crescent/utils/tests')
local hash = require('../crescent/utils/hash')

local hashTests = {
    testeSamePass = function()
        local password = "password123"
        local hashed1 = hash.encrypt(password, 10000)
        local hashed2 = hash.encrypt(password, 10000)
        tests.assertNotEquals(hashed1, hashed2, "Hashes should be different due to random salt")
    end,
    
    testeVerifyCorrectPassword = function()
        local password = "mySecretPass123"
        local hashed = hash.encrypt(password)
        tests.assertTrue(hash.verify(password, hashed), "Should verify correct password")
    end,
    
    testeVerifyIncorrectPassword = function()
        local password = "mySecretPass123"
        local wrongPassword = "wrongPassword"
        local hashed = hash.encrypt(password)
        tests.assertFalse(hash.verify(wrongPassword, hashed), "Should reject incorrect password")
    end,
    
    testeHashFormat = function()
        local password = "test123"
        local hashed = hash.encrypt(password)
        -- Formato deve ser: iterations$salt$hash
        local parts = {}
        for part in string.gmatch(hashed, "[^$]+") do
            table.insert(parts, part)
        end
        tests.assertEquals(#parts, 3, "Hash should have 3 parts separated by $")
        tests.assertType(tonumber(parts[1]), "number", "First part should be iterations number")
    end,
    
    testeCustomIterations = function()
        local password = "test123"
        local hashed = hash.encrypt(password, 5000)
        tests.assertTrue(string.find(hashed, "^5000%$"), "Hash should start with custom iterations")
    end,
    
    testeSha256Hash = function()
        local data = "Hello World"
        local hashed = hash.sha256(data)
        tests.assertNotNil(hashed, "SHA256 hash should not be nil")
        tests.assertIsString(hashed, "SHA256 hash should be a string")
    end,
    
    testeMd5Hash = function()
        local data = "Hello World"
        local hashed = hash.md5(data)
        tests.assertNotNil(hashed, "MD5 hash should not be nil")
        tests.assertIsString(hashed, "MD5 hash should be a string")
    end,
    
    testeSecureCompare = function()
        local str1 = "same_string"
        local str2 = "same_string"
        local str3 = "different"
        tests.assertTrue(hash.secureCompare(str1, str2), "Same strings should match")
        tests.assertFalse(hash.secureCompare(str1, str3), "Different strings should not match")
    end,
    
    testeEmptyPassword = function()
        tests.assertError(function()
            hash.encrypt("")
        end, "Password must be a non-empty string")
    end,
    
    testeAliases = function()
        local password = "test123"
        -- Testa se os aliases funcionam
        local hashed1 = hash.encrypt(password)
        local hashed2 = hash.encript(password)
        tests.assertNotNil(hashed1, "encrypt should work")
        tests.assertNotNil(hashed2, "encript alias should work")
        
        -- Testa verify aliases
        tests.assertTrue(hash.verify(password, hashed1), "verify should work")
        tests.assertTrue(hash.decrypt(password, hashed1), "decrypt alias should work")
        tests.assertTrue(hash.decript(password, hashed1), "decript alias should work")
    end
}

tests.runSuite("Hash Utility Tests", hashTests)