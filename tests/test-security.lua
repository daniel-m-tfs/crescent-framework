-- tests/test-security.lua
-- Cobre as correções de segurança da Fase 1: path traversal (static.lua),
-- decode real de Basic Auth (auth.lua) e escaping de identificador em
-- JOIN/ORDER BY (query_builder.lua)

local tests = require('../crescent/utils/tests')
local path_utils = require('../crescent/utils/path')
local base64 = require('../crescent/utils/base64')
local static = require('../crescent/middleware/static')
local auth = require('../crescent/middleware/auth')
local QB = require('../crescent/database/query_builder')
local sql_escape = require('../crescent/database/sql_escape')

-- Cria um ctx mínimo o suficiente para exercitar os middlewares testados aqui
local function mock_ctx(overrides)
    overrides = overrides or {}
    local sent_status, sent_body

    local ctx = {
        method = overrides.method or "GET",
        path = overrides.path,
        state = {},
        req = { socket = {} },
        res = {
            finished = false,
            headers = {},
            setHeader = function(self, name, value) self.headers[name] = value end,
            writeHead = function(self, status) sent_status = status end,
            finish = function(self, body) sent_body = body end,
        },
    }

    local headers = overrides.headers or {}
    ctx.getHeader = function(name)
        return headers[string.lower(name)]
    end

    ctx.error = function(status, message)
        sent_status = status
        sent_body = message
        return true
    end

    ctx.getStatus = function() return sent_status end
    ctx.getBody = function() return sent_body end

    return ctx
end

local securityTests = {
    -- ==========================================
    -- PATH TRAVERSAL (crescent/utils/path.is_safe)
    -- ==========================================

    testePathIsSafeRejectsDotDot = function()
        tests.assertFalse(path_utils.is_safe("/../../etc/passwd"), "'..' deve ser rejeitado")
        tests.assertFalse(path_utils.is_safe("/public/../../secret.txt"), "'..' no meio deve ser rejeitado")
        tests.assertFalse(path_utils.is_safe("..%2f..%2fetc%2fpasswd"), "'..' cru continua rejeitado mesmo com encoding ao redor")
    end,

    testePathIsSafeRejectsNullByte = function()
        tests.assertFalse(path_utils.is_safe("/public/file.txt\0.png"), "null byte deve ser rejeitado")
    end,

    testePathIsSafeAcceptsNormalPaths = function()
        tests.assertTrue(path_utils.is_safe("/css/app.css"), "path normal deve ser aceito")
        tests.assertTrue(path_utils.is_safe("/img/logo.png"), "path normal deve ser aceito")
    end,

    testeStaticMiddlewareBlocksTraversal = function()
        local middleware = static.create("public")
        local ctx = mock_ctx({ path = "/../../../../etc/passwd" })

        local called_next = false
        local next_fn = function() called_next = true; return true end

        middleware(ctx, next_fn)

        tests.assertTrue(called_next, "middleware deve chamar next() em vez de tentar ler o arquivo")
        tests.assertFalse(ctx.res.finished, "resposta não deve ser finalizada para path traversal")
    end,

    testeStaticMiddlewareServesNormalPath = function()
        -- Serve o próprio arquivo de teste como "estático" pra confirmar que
        -- paths legítimos continuam funcionando após a correção
        local middleware = static.create(".")
        local ctx = mock_ctx({ path = "/tests/test-security.lua" })

        local called_next = false
        middleware(ctx, function() called_next = true; return true end)

        tests.assertFalse(called_next, "arquivo existente não deve cair no next()")
        tests.assertTrue(ctx.res.finished, "resposta deve ser finalizada ao servir o arquivo")
    end,

    -- ==========================================
    -- BASIC AUTH DECODE (crescent/utils/base64 + middleware/auth)
    -- ==========================================

    testeBase64RoundTrip = function()
        local original = "admin:s3cr3t!"
        local encoded = base64.encode(original)
        tests.assertEquals(base64.decode(encoded), original, "decode(encode(x)) deve retornar x")
    end,

    testeBase64DecodeInvalidReturnsNil = function()
        tests.assertNil(base64.decode("not-valid-base64!!"), "entrada inválida deve retornar nil, não erro")
    end,

    testeBase64DecodeRejectsMisplacedPadding = function()
        -- Regressão: b64lookup["="]=0 fazia um "=" fora de posição virar
        -- silenciosamente um "A" em vez de invalidar o decode.
        tests.assertNil(base64.decode("=AAA"), "'=' na 1a posição deve invalidar")
        tests.assertNil(base64.decode("A=AA"), "'=' na 2a posição deve invalidar")
        tests.assertNil(base64.decode("AA=A"), "'=' seguido de caractere de dado deve invalidar")
        tests.assertNotNil(base64.decode("AA=="), "padding válido no final deve continuar funcionando")
        tests.assertNotNil(base64.decode("AAA="), "padding válido no final deve continuar funcionando")
    end,

    testeBase64EmptyStringRoundTrip = function()
        tests.assertEquals(base64.decode(base64.encode("")), "", "string vazia deve fazer round-trip")
    end,

    testeBasicAuthDecodesRealCredentials = function()
        local credentials = base64.encode("admin:s3cr3t!")
        local ctx = mock_ctx({
            headers = { authorization = "Basic " .. credentials }
        })

        local captured_user, captured_pass
        local validator = function(user, pass, _ctx)
            captured_user, captured_pass = user, pass
            return true, { username = user }
        end

        local middleware = auth.basic(validator)
        local called_next = false
        middleware(ctx, function() called_next = true; return true end)

        tests.assertEquals(captured_user, "admin", "usuário deve ser decodificado corretamente")
        tests.assertEquals(captured_pass, "s3cr3t!", "senha deve ser decodificada corretamente")
        tests.assertTrue(called_next, "next() deve ser chamado com credenciais válidas")
    end,

    testeBasicAuthRejectsMalformedBase64 = function()
        local ctx = mock_ctx({
            headers = { authorization = "Basic %%%not-base64%%%" }
        })

        local validator_called = false
        local validator = function() validator_called = true; return true, {} end

        local middleware = auth.basic(validator)
        middleware(ctx, function() return true end)

        tests.assertFalse(validator_called, "validator não deve ser chamado com base64 inválido")
        tests.assertEquals(ctx.getStatus(), 401, "deve responder 401 para base64 inválido")
    end,

    -- ==========================================
    -- ESCAPING DE IDENTIFICADOR (JOIN / ORDER BY)
    -- ==========================================

    testeEscapeIdentifierWrapsInBackticks = function()
        tests.assertEquals(sql_escape.escape_identifier("users"), "`users`", "identificador simples")
        tests.assertEquals(sql_escape.escape_identifier("users.id"), "`users`.`id`", "identificador qualificado")
    end,

    testeJoinEscapesIdentifiers = function()
        local sql = QB.table("orders")
            :join("other_table", "orders.user_id", "=", "users.id")
            :toSql()

        tests.assertContains(sql, "`orders`.`user_id`", "coluna do JOIN deve ser escapada")
        tests.assertContains(sql, "`users`.`id`", "coluna do JOIN deve ser escapada")
    end,

    testeJoinRejectsMaliciousIdentifier = function()
        -- escape_identifier() agora valida cada segmento contra uma whitelist
        -- (letras/números/underscore) e rejeita com erro em vez de aceitar
        -- silenciosamente um identificador malicioso entre backticks.
        local ok, err = pcall(function()
            return QB.table("orders")
                :join("users; DROP TABLE users; --", "orders.user_id", "=", "users.id")
                :toSql()
        end)

        tests.assertFalse(ok, "identificador malicioso em JOIN deve lançar erro, não virar SQL")
        tests.assertContains(tostring(err), "Invalid SQL identifier",
            "erro deve indicar identificador inválido")
    end,

    testeOrderByEscapesIdentifierAndWhitelistsDirection = function()
        local sql = QB.table("users"):orderBy("name", "ASC; DROP TABLE users; --"):toSql()

        tests.assertContains(sql, "`name`", "coluna do ORDER BY deve ser escapada")
        tests.assertNotContains(sql, "DROP TABLE", "direction maliciosa deve ser filtrada, não interpolada")
        tests.assertMatches(sql, "ORDER BY `name` ASC$", "direction inválida deve cair no default ASC")
    end,

    testeOrderByAcceptsDesc = function()
        local sql = QB.table("users"):orderBy("created_at", "DESC"):toSql()
        tests.assertMatches(sql, "ORDER BY `created_at` DESC$", "DESC explícito deve ser preservado")
    end,

    testeEscapeValueRemovesNullBytes = function()
        -- "\0" literal dentro de gsub NÃO casa nada nesta engine Lua/LuaJIT
        -- (silenciosamente vira no-op) — precisa ser "%z". Regressão direta
        -- de um bug de segurança real (SECURITY.md promete essa remoção).
        local escaped = sql_escape.escape_value("abc\0def")
        tests.assertNotContains(escaped, "\0", "byte nulo deve ser removido do valor escapado")
        tests.assertEquals(escaped, "'abcdef'", "byte nulo deve ser removido, resto do valor preservado")
    end,

    testeEscapeIdentifierRejectsInvalidCharacters = function()
        local ok = pcall(sql_escape.escape_identifier, "id; DROP TABLE users; --")
        tests.assertFalse(ok, "identificador com caracteres fora da whitelist deve ser rejeitado")
    end,

    testeEscapeIdentifierAcceptsQualifiedName = function()
        local escaped = sql_escape.escape_identifier("users.id")
        tests.assertEquals(escaped, "`users`.`id`", "identificador qualificado válido deve ser aceito normalmente")
    end,
}

tests.runSuite("Security Fixes (Fase 1)", securityTests)
