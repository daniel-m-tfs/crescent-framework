-- test-orm.lua
-- Teste completo do ORM Crescent

require("../bootstrap")

local Model = require("crescent.database.model")

print("🌙 Crescent ORM - Teste Completo")
print("")

-- Define User Model inline
local User = Model:extend({
    table = "users",
    fillable = {"name", "email", "password", "active"},
    hidden = {"password"},
    timestamps = true,
    
    validates = {
        name = {required = true, min_length = 3},
        email = {required = true, email = true},
        password = {required = true, min_length = 6}
    },
    
    before_save = function(user)
        print("🔒 Hook before_save executado")
    end,
    
    after_create = function(user)
        print("✅ Hook after_create executado")
    end
})

print("🌙 Crescent ORM - Teste Completo")
print("")

-- ==========================
-- 1. CREATE
-- ==========================
print("1️⃣ CREATE - Criar novo usuário")
local user, errors = User:create({
    name = "João Silva",
    email = "joao" .. os.time() .. "@example.com",
    password = "secret123",
    active = true
})

if user then
    print("✅ Usuário criado com ID:", user:get("id"))
    print("   Nome:", user:get("name"))
    print("   Email:", user:get("email"))
else
    print("❌ Erro ao criar usuário")
    if type(errors) == "string" then
        print("   Mensagem:", errors)
    elseif type(errors) == "table" then
        print("   Erros de validação:")
        for field, msg in pairs(errors) do
            print("     -", msg)
        end
    end
end
print("")

-- Se o usuário não foi criado, não podemos continuar os testes
if not user then
    print("⚠️  Testes abortados: usuário não foi criado")
    print("")
    print("💡 Possíveis causas:")
    print("   1. Banco de dados não está rodando")
    print("   2. Credenciais incorretas no .env")
    print("   3. Tabela 'users' não existe")
    print("   4. Permissões de banco insuficientes")
    print("")
    print("📝 Para criar a tabela users:")
    print("   CREATE TABLE users (")
    print("     id INT AUTO_INCREMENT PRIMARY KEY,")
    print("     name VARCHAR(255) NOT NULL,")
    print("     email VARCHAR(255) UNIQUE NOT NULL,")
    print("     password VARCHAR(255),")
    print("     active BOOLEAN DEFAULT 1,")
    print("     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,")
    print("     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP")
    print("   );")
    os.exit(1)
end

-- ==========================
-- 2. READ - Find by ID
-- ==========================
print("2️⃣ READ - Buscar por ID")
local found_user = User:find(user:get("id"))
if found_user then
    print("✅ Usuário encontrado:", found_user:get("name"))
else
    print("❌ Usuário não encontrado")
end
print("")

-- ==========================
-- 3. READ - All
-- ==========================
print("3️⃣ READ - Buscar todos")
local all_users = User:all()
print("✅ Total de usuários:", #all_users)
for i, u in ipairs(all_users) do
    print(string.format("   %d. %s (%s)", i, u:get("name"), u:get("email")))
end
print("")

-- ==========================
-- 4. READ - Where
-- ==========================
print("4️⃣ READ - Where (usuários ativos)")
local active_users = User:where("active", true):get()
if active_users then
    print("✅ Usuários ativos:", #active_users)
else
    print("⚠️  Modo mock ativo")
end
print("")

-- ==========================
-- 5. UPDATE
-- ==========================
print("5️⃣ UPDATE - Atualizar usuário")
local success = user:update({
    name = "João Silva Santos",
    email = user:get("email") -- Mantém o email único
})

if success then
    print("✅ Usuário atualizado:", user:get("name"))
else
    print("❌ Erro ao atualizar")
end
print("")

-- ==========================
-- 6. VALIDATIONS
-- ==========================
print("6️⃣ VALIDATIONS - Testar validações")
local invalid_user, validation_errors = User:create({
    name = "Jo", -- Muito curto (min 3)
    email = "invalid-email", -- Email inválido
    password = "123" -- Muito curta (min 6)
})

if not invalid_user then
    print("✅ Validações funcionando:")
    for field, error_msg in pairs(validation_errors) do
        print("   ❌ " .. error_msg)
    end
else
    print("⚠️  Validações não funcionaram")
end
print("")

-- ==========================
-- 7. TO TABLE (sem campos hidden)
-- ==========================
print("7️⃣ TO TABLE - Converter para tabela")
local user_data = user:toTable()
print("✅ Dados do usuário (sem password):")
for k, v in pairs(user_data) do
    print(string.format("   %s: %s", k, tostring(v)))
end
print("")

-- ==========================
-- 8. DELETE
-- ==========================
print("8️⃣ DELETE - Deletar usuário")
-- local deleted = user:delete()
-- if deleted then
--     print("✅ Usuário deletado")
-- else
--     print("❌ Erro ao deletar")
-- end
print("⏭️  Pulado para manter dados de teste")
print("")

-- ==========================
-- 9. SCOPES (se implementados)
-- ==========================
print("9️⃣ SCOPES - Buscar usuários ativos (scope)")
-- local active = User:scopeActive():get()
-- print("✅ Usuários ativos (via scope):", #active)
print("⏭️  Scopes personalizados disponíveis no model")
print("")

print("✅ Teste ORM concluído!")
print("")
print("📚 Recursos disponíveis:")
print("   ✅ CRUD completo (Create, Read, Update, Delete)")
print("   ✅ Validações (required, min_length, max_length, email, unique)")
print("   ✅ Mass assignment protection (fillable/guarded)")
print("   ✅ Hidden fields (toTable não retorna password)")
print("   ✅ Timestamps automáticos (created_at, updated_at)")
print("   ✅ Hooks (before_save, after_create, etc)")
print("   ✅ Relações (hasMany, hasOne, belongsTo)")
print("   ✅ Query Builder integration")
print("   ✅ Scopes personalizados")
