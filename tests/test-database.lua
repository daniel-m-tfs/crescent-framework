-- tests/test-database.lua
-- Testes determinísticos do Query Builder que não dependem de um MySQL real.

local tests = require('../crescent/utils/tests')
local QB = require('../crescent/database/query_builder')

local databaseTests = {
    testeNormalizaTabelaESelecao = function()
        local sql = QB.table("users"):select("users.id", "users.name"):toSql()
        tests.assertContains(sql, "FROM `users`", "tabela deve ser escapada")
        tests.assertContains(sql, "`users`.`id`, `users`.`name`", "colunas devem ser escapadas")
    end,

    testeWhereNilViraIsNull = function()
        local sql = QB.table("users"):where("deleted_at", nil):toSql()
        tests.assertContains(sql, "`deleted_at` IS NULL", "valor nil deve gerar IS NULL")
    end,

    testeOrWhereNilViraOrIsNull = function()
        local sql = QB.table("users")
            :where("active", true)
            :orWhere("deleted_at", nil)
            :toSql()
        tests.assertContains(sql, "OR `deleted_at` IS NULL", "orWhere nil deve gerar OR IS NULL")
    end,

    testeWhereInVazioNaoGeraSqlInvalido = function()
        local sql = QB.table("users"):whereIn("id", {}):toSql()
        tests.assertContains(sql, "WHERE 1 = 0", "lista vazia deve nunca casar")
        tests.assertNotContains(sql, "IN ()", "não deve gerar IN vazio")
    end,

    testeRejeitaOperadorMalicioso = function()
        local ok = pcall(function()
            QB.table("users"):where("id", "= 1; DROP TABLE users; --", 1):toSql()
        end)
        tests.assertFalse(ok, "operador arbitrário deve ser rejeitado")
    end,

    testeValidaPaginacao = function()
        local ok = pcall(function() QB.table("users"):limit(-1) end)
        tests.assertFalse(ok, "LIMIT negativo deve ser rejeitado")

        local sql = QB.table("users"):paginate(2, 10):toSql()
        tests.assertContains(sql, "LIMIT 10 OFFSET 10", "paginação deve calcular offset")
    end,

    testeJoinNormalizaIdentificadores = function()
        local sql = QB.table("orders")
            :join("users", "orders.user_id", "=", "users.id")
            :toSql()
        tests.assertContains(sql, "JOIN `users` ON `orders`.`user_id` = `users`.`id`", "JOIN deve escapar identificadores")
    end,
}

tests.runSuite("Database Query Builder", databaseTests)
