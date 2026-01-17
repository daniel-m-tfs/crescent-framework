local tests = require('../crescent/utils/tests')
local jwt = require('../crescent/utils/jwt')
local auth = require('../crescent/middleware/auth')

-- Secret para testes
local TEST_SECRET = "test_secret_key_super_secure_123456"

local authTests = {
    -- ==========================================
    -- TESTES JWT BÁSICOS
    -- ==========================================
    
    testeJwtSignAndVerify = function()
        local payload = {
            user_id = 1,
            username = "testuser",
            email = "test@example.com"
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        tests.assertNotNil(token, "Token should not be nil")
        tests.assertIsString(token, "Token should be a string")
        
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        tests.assertTrue(ok, "Token verification should succeed")
        tests.assertEquals(decoded.user_id, 1, "User ID should match")
        tests.assertEquals(decoded.username, "testuser", "Username should match")
        tests.assertEquals(decoded.email, "test@example.com", "Email should match")
    end,
    
    testeJwtWithExpiration = function()
        local payload = {
            user_id = 1,
            username = "testuser"
        }
        
        -- Token que expira em 1 segundo
        local token = jwt.sign(payload, TEST_SECRET, {
            expiresIn = 1
        })
        
        -- Deve verificar com sucesso imediatamente
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        tests.assertTrue(ok, "Token should be valid immediately")
        tests.assertNotNil(decoded.exp, "Token should have expiration claim")
    end,
    
    testeJwtInvalidSignature = function()
        local payload = {
            user_id = 1,
            username = "testuser"
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        local ok, error_msg = jwt.verify(token, "wrong_secret")
        
        tests.assertFalse(ok, "Verification should fail with wrong secret")
        tests.assertNotNil(error_msg, "Should return error message")
    end,
    
    testeJwtInvalidFormat = function()
        local invalid_tokens = {
            "invalid.token",
            "invalid",
            "",
            "a.b.c.d", -- 4 parts
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" -- only header
        }
        
        for _, token in ipairs(invalid_tokens) do
            local ok, error_msg = jwt.verify(token, TEST_SECRET)
            tests.assertFalse(ok, "Invalid token format should fail: " .. token)
        end
    end,
    
    testeJwtDecode = function()
        local payload = {
            user_id = 1,
            username = "testuser"
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        local header, decoded_payload = jwt.decode(token)
        
        tests.assertNotNil(header, "Header should not be nil")
        tests.assertNotNil(decoded_payload, "Payload should not be nil")
        tests.assertEquals(header.alg, "HS256", "Algorithm should be HS256")
        tests.assertEquals(header.typ, "JWT", "Type should be JWT")
        tests.assertEquals(decoded_payload.user_id, 1, "User ID should match")
        tests.assertEquals(decoded_payload.username, "testuser", "Username should match")
    end,
    
    testeJwtWithIssuer = function()
        local payload = {
            user_id = 1
        }
        
        local token = jwt.sign(payload, TEST_SECRET, {
            issuer = "crescent-app"
        })
        
        -- Verifica com issuer correto
        local ok, decoded = jwt.verify(token, TEST_SECRET, {
            issuer = "crescent-app"
        })
        tests.assertTrue(ok, "Should verify with correct issuer")
        tests.assertEquals(decoded.iss, "crescent-app", "Issuer should match")
        
        -- Verifica com issuer incorreto
        ok, error_msg = jwt.verify(token, TEST_SECRET, {
            issuer = "wrong-issuer"
        })
        tests.assertFalse(ok, "Should fail with wrong issuer")
    end,
    
    testeJwtWithAudience = function()
        local payload = {
            user_id = 1
        }
        
        local token = jwt.sign(payload, TEST_SECRET, {
            audience = "api-users"
        })
        
        -- Verifica com audience correto
        local ok, decoded = jwt.verify(token, TEST_SECRET, {
            audience = "api-users"
        })
        tests.assertTrue(ok, "Should verify with correct audience")
        tests.assertEquals(decoded.aud, "api-users", "Audience should match")
        
        -- Verifica com audience incorreto
        ok, error_msg = jwt.verify(token, TEST_SECRET, {
            audience = "wrong-audience"
        })
        tests.assertFalse(ok, "Should fail with wrong audience")
    end,
    
    testeJwtWithNotBefore = function()
        local payload = {
            user_id = 1
        }
        
        -- Token que só será válido daqui a 2 segundos
        local token = jwt.sign(payload, TEST_SECRET, {
            notBefore = 2
        })
        
        local ok, error_msg = jwt.verify(token, TEST_SECRET)
        tests.assertFalse(ok, "Token should not be valid yet")
        tests.assertTrue(error_msg:find("not yet valid") ~= nil, "Error should mention 'not yet valid'")
    end,
    
    testeJwtIssuedAt = function()
        local payload = {
            user_id = 1
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        
        tests.assertTrue(ok, "Token should be valid")
        tests.assertNotNil(decoded.iat, "Token should have issued at claim")
        tests.assertType(decoded.iat, "number", "Issued at should be a number")
    end,
    
    -- ==========================================
    -- TESTES DE ACCESS E REFRESH TOKENS
    -- ==========================================
    
    testeCreateAccessToken = function()
        local payload = {
            user_id = 1,
            username = "testuser"
        }
        
        local token = jwt.create_access_token(payload, TEST_SECRET)
        tests.assertNotNil(token, "Access token should not be nil")
        
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        tests.assertTrue(ok, "Access token should be valid")
        tests.assertNotNil(decoded.exp, "Access token should have expiration")
    end,
    
    testeCreateRefreshToken = function()
        local payload = {
            user_id = 1,
            username = "testuser"
        }
        
        local token = jwt.create_refresh_token(payload, TEST_SECRET)
        tests.assertNotNil(token, "Refresh token should not be nil")
        
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        tests.assertTrue(ok, "Refresh token should be valid")
        tests.assertNotNil(decoded.exp, "Refresh token should have expiration")
    end,
    
    testeCreateAccessTokenCustomExpiry = function()
        local payload = {
            user_id = 1
        }
        
        local custom_expiry = 3600 -- 1 hora
        local token = jwt.create_access_token(payload, TEST_SECRET, custom_expiry)
        
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        tests.assertTrue(ok, "Token should be valid")
        
        -- Verifica que a expiração está correta (com margem de 1 segundo)
        local expected_exp = decoded.iat + custom_expiry
        tests.assertTrue(math.abs(decoded.exp - expected_exp) <= 1, "Expiration should match custom value")
    end,
    
    -- ==========================================
    -- TESTES DO MIDDLEWARE AUTH
    -- ==========================================
    
    testeGenerateToken = function()
        local payload = {
            user_id = 1,
            username = "testuser"
        }
        
        local token = auth.generate_token(payload, {
            secret = TEST_SECRET,
            expiresIn = 3600
        })
        
        tests.assertNotNil(token, "Generated token should not be nil")
        tests.assertIsString(token, "Generated token should be a string")
        
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        tests.assertTrue(ok, "Generated token should be valid")
        tests.assertEquals(decoded.user_id, 1, "User ID should match")
    end,
    
    testeGenerateTokenPair = function()
        local payload = {
            user_id = 1,
            username = "testuser"
        }
        
        local tokens = auth.generate_token_pair(payload, {
            secret = TEST_SECRET
        })
        
        tests.assertNotNil(tokens, "Token pair should not be nil")
        tests.assertNotNil(tokens.access_token, "Access token should not be nil")
        tests.assertNotNil(tokens.refresh_token, "Refresh token should not be nil")
        tests.assertEquals(tokens.token_type, "Bearer", "Token type should be Bearer")
        tests.assertType(tokens.expires_in, "number", "Expires in should be a number")
        
        -- Verifica ambos os tokens
        local ok_access, decoded_access = jwt.verify(tokens.access_token, TEST_SECRET)
        local ok_refresh, decoded_refresh = jwt.verify(tokens.refresh_token, TEST_SECRET)
        
        tests.assertTrue(ok_access, "Access token should be valid")
        tests.assertTrue(ok_refresh, "Refresh token should be valid")
        tests.assertEquals(decoded_access.user_id, 1, "Access token user ID should match")
        tests.assertEquals(decoded_refresh.user_id, 1, "Refresh token user ID should match")
    end,
    
    testeVerifyTokenHelper = function()
        local payload = {
            user_id = 1
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        
        local ok, decoded = auth.verify_token(token, {
            secret = TEST_SECRET
        })
        
        tests.assertTrue(ok, "Token verification should succeed")
        tests.assertEquals(decoded.user_id, 1, "User ID should match")
        
        -- Teste com token inválido
        ok, error_msg = auth.verify_token(token, {
            secret = "wrong_secret"
        })
        tests.assertFalse(ok, "Verification should fail with wrong secret")
    end,
    
    testeDecodeTokenHelper = function()
        local payload = {
            user_id = 1,
            username = "testuser"
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        local header, decoded = auth.decode_token(token)
        
        tests.assertNotNil(header, "Header should not be nil")
        tests.assertNotNil(decoded, "Decoded payload should not be nil")
        tests.assertEquals(decoded.user_id, 1, "User ID should match")
        tests.assertEquals(decoded.username, "testuser", "Username should match")
    end,
    
    -- ==========================================
    -- TESTES DE CASOS ESPECIAIS
    -- ==========================================
    
    testeJwtWithComplexPayload = function()
        local payload = {
            user_id = 1,
            username = "testuser",
            roles = {"admin", "user"},
            permissions = {
                read = true,
                write = true,
                delete = false
            },
            metadata = {
                created_at = 1234567890,
                last_login = 9876543210
            }
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        
        tests.assertTrue(ok, "Token with complex payload should be valid")
        tests.assertEquals(decoded.user_id, 1, "User ID should match")
        tests.assertEquals(#decoded.roles, 2, "Should have 2 roles")
        tests.assertEquals(decoded.roles[1], "admin", "First role should be admin")
        tests.assertTrue(decoded.permissions.read, "Read permission should be true")
        tests.assertFalse(decoded.permissions.delete, "Delete permission should be false")
        tests.assertEquals(decoded.metadata.created_at, 1234567890, "Metadata should match")
    end,
    
    testeJwtWithUnicodeCharacters = function()
        local payload = {
            user_id = 1,
            name = "José da Silva",
            location = "São Paulo, Brasil",
            message = "Olá! 你好 🚀"
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        
        tests.assertTrue(ok, "Token with unicode should be valid")
        tests.assertEquals(decoded.name, "José da Silva", "Name with accent should match")
        tests.assertEquals(decoded.location, "São Paulo, Brasil", "Location should match")
        tests.assertEquals(decoded.message, "Olá! 你好 🚀", "Message with emoji should match")
    end,
    
    testeJwtEmptyPayload = function()
        local payload = {}
        
        local token = jwt.sign(payload, TEST_SECRET)
        tests.assertNotNil(token, "Token with empty payload should be created")
        
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        tests.assertTrue(ok, "Empty payload token should be valid")
        tests.assertNotNil(decoded.iat, "Should have issued at claim even with empty payload")
    end,
    
    testeJwtVeryLongPayload = function()
        local payload = {
            user_id = 1,
            description = string.rep("a", 10000) -- 10k caracteres
        }
        
        local token = jwt.sign(payload, TEST_SECRET)
        tests.assertNotNil(token, "Token with long payload should be created")
        
        local ok, decoded = jwt.verify(token, TEST_SECRET)
        tests.assertTrue(ok, "Long payload token should be valid")
        tests.assertEquals(#decoded.description, 10000, "Long description should match")
    end,
    
    testeJwtSpecialCharactersInSecret = function()
        local special_secret = "my@secret#key$with%special^chars&123*()_+-=[]{}|;:',.<>?/"
        local payload = {
            user_id = 1
        }
        
        local token = jwt.sign(payload, special_secret)
        local ok, decoded = jwt.verify(token, special_secret)
        
        tests.assertTrue(ok, "Token with special chars in secret should work")
        tests.assertEquals(decoded.user_id, 1, "User ID should match")
        
        -- Verifica que outro secret não funciona
        ok, error_msg = jwt.verify(token, TEST_SECRET)
        tests.assertFalse(ok, "Different secret should not verify")
    end,
    
    -- ==========================================
    -- TESTES DE ERROS E VALIDAÇÕES
    -- ==========================================
    
    testeJwtErrorMissingSecret = function()
        local ok, err = pcall(function()
            jwt.sign({user_id = 1}, "")
        end)
        tests.assertFalse(ok, "Should error with empty secret")
    end,
    
    testeJwtErrorInvalidPayloadType = function()
        local ok, err = pcall(function()
            jwt.sign("not a table", TEST_SECRET)
        end)
        tests.assertFalse(ok, "Should error with non-table payload")
    end,
    
    testeJwtErrorEmptyToken = function()
        local ok, error_msg = jwt.verify("", TEST_SECRET)
        tests.assertFalse(ok, "Empty token should fail")
        tests.assertNotNil(error_msg, "Should return error message")
    end,
    
    testeJwtErrorNilToken = function()
        local ok, error_msg = jwt.verify(nil, TEST_SECRET)
        tests.assertFalse(ok, "Nil token should fail")
    end,
    
    testeJwtMultipleTokensIndependent = function()
        local payload1 = { user_id = 1 }
        local payload2 = { user_id = 2 }
        local payload3 = { user_id = 3 }
        
        local token1 = jwt.sign(payload1, TEST_SECRET)
        local token2 = jwt.sign(payload2, TEST_SECRET)
        local token3 = jwt.sign(payload3, TEST_SECRET)
        
        tests.assertNotEquals(token1, token2, "Different payloads should create different tokens")
        tests.assertNotEquals(token2, token3, "Different payloads should create different tokens")
        tests.assertNotEquals(token1, token3, "Different payloads should create different tokens")
        
        local ok1, decoded1 = jwt.verify(token1, TEST_SECRET)
        local ok2, decoded2 = jwt.verify(token2, TEST_SECRET)
        local ok3, decoded3 = jwt.verify(token3, TEST_SECRET)
        
        tests.assertTrue(ok1 and ok2 and ok3, "All tokens should be valid")
        tests.assertEquals(decoded1.user_id, 1, "Token 1 user ID should be 1")
        tests.assertEquals(decoded2.user_id, 2, "Token 2 user ID should be 2")
        tests.assertEquals(decoded3.user_id, 3, "Token 3 user ID should be 3")
    end
}

-- Executa os testes
-- print("\n" .. string.rep("=", 60))
-- print("🔐 TESTES DE AUTENTICAÇÃO (JWT)")
-- print(string.rep("=", 60) .. "\n")

tests.runSuite("Testes auth", authTests)

-- print("\n" .. string.rep("=", 60))
-- print("✅ TESTES CONCLUÍDOS")
-- print(string.rep("=", 60) .. "\n")
