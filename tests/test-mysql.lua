-- test-mysql.lua
-- Teste de conexão e query builder com MySQL

require("../bootstrap")

local MySQL = require("crescent.database.mysql")
local DB = require("crescent.database.query_builder")
local TEST_TABLE = "crescent_framework_mysql_test_users"

print("🌙 Crescent Framework - Teste MySQL")
print("")

-- Testa conexão
print("1️⃣ Testando conexão...")
MySQL.test()
print("")

-- Cria tabela de exemplo (se não existir)
print("2️⃣ Criando tabela de teste (se não existir)...")
local create_table = string.format([[
    CREATE TABLE IF NOT EXISTS `%s` (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        active BOOLEAN DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
]], TEST_TABLE)

local result, err = MySQL:query("DROP TABLE IF EXISTS `" .. TEST_TABLE .. "`")
if not result and err then
    print("❌ Erro ao limpar tabela de teste:", err)
    os.exit(1)
end

result, err = MySQL:query(create_table)
if err then
    print("❌ Erro:", err)
else
    print("✓ Tabela criada/verificada")
end
print("")

-- INSERT com Query Builder
print("3️⃣ Inserindo usuário...")
local user_id = DB.table(TEST_TABLE):insert({
    name = "João Silva",
    email = "joao" .. os.time() .. "@example.com", -- Email único
    active = true
})

if user_id then
    print("✓ Usuário inserido com ID:", user_id)
else
    print("❌ Erro ao inserir")
end
print("")

-- SELECT com Query Builder
print("4️⃣ Buscando usuários ativos...")
local users = DB.table(TEST_TABLE)
    :where("active", true)
    :orderBy("created_at", "DESC")
    :limit(5)
    :get()

if users then
    print("✓ Encontrados", #users, "usuário(s):")
    for i, user in ipairs(users) do
        print(string.format("  %d. %s (%s)", i, user.name, user.email))
    end
else
    print("❌ Erro ao buscar usuários")
end
print("")

-- UPDATE com Query Builder
print("5️⃣ Atualizando usuário...")
local update_result = DB.table(TEST_TABLE)
    :where("id", user_id)
    :update({ name = "João Silva Santos" })

if update_result then
    print("✓ Linhas afetadas:", update_result.affected or 0)
else
    print("❌ Erro ao atualizar")
end
print("")

-- SELECT específico
print("6️⃣ Buscando usuário atualizado...")
local updated_user = DB.table(TEST_TABLE)
    :where("id", user_id)
    :first()

if updated_user then
    print("✓ Usuário encontrado:", updated_user.name)
else
    print("❌ Usuário não encontrado")
end
print("")

-- COUNT
print("7️⃣ Contando usuários ativos...")
local count = DB.table(TEST_TABLE)
    :where("active", true)
    :count()
print("✓ Total:", count)
print("")

-- DELETE (opcional - comente se quiser manter os dados)
-- print("8️⃣ Deletando usuário de teste...")
-- local delete_result = DB.table("users")
--     :where("id", user_id)
--     :delete()
-- if delete_result then
--     print("✓ Linhas deletadas:", delete_result.affected or 0)
-- end

-- Fecha conexões
MySQL:query("DROP TABLE IF EXISTS `" .. TEST_TABLE .. "`")
MySQL.closeAll()

print("✅ Teste concluído!")
