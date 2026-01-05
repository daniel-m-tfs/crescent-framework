-- test.lua
-- Testes básicos do framework Crescent

local crescent = require("crescent")

print("🧪 Iniciando testes do Crescent Framework...")
print("=" .. string.rep("=", 50))

-- Teste 1: Criação do servidor
print("\n✓ Teste 1: Criação do servidor")
local app = crescent.new()
assert(app ~= nil, "Servidor não foi criado")
print("  Servidor criado com sucesso")

-- Teste 2: Adicionar rotas
print("\n✓ Teste 2: Adicionar rotas")
app:get("/test", function(ctx)
    return ctx.json(200, {test = true})
end)
print("  Rota GET /test adicionada")

app:post("/test", function(ctx)
    return ctx.json(201, {created = true})
end)
print("  Rota POST /test adicionada")

-- Teste 3: Grupos de rotas
print("\n✓ Teste 3: Grupos de rotas")
app:group("/api", function(app)
    app:get("/users", function(ctx)
        return {users = {}}
    end)
end)
print("  Grupo /api criado com rota /users")

-- Teste 4: Middlewares
print("\n✓ Teste 4: Middlewares")
app:use(crescent.middleware.logger.basic())
print("  Logger middleware adicionado")

app:use(crescent.middleware.cors.default())
print("  CORS middleware adicionado")

app:use(crescent.middleware.security.headers())
print("  Security headers middleware adicionado")

-- Teste 5: Utils
print("\n✓ Teste 5: Utils")

-- String utils
local str = "  test  "
local trimmed = crescent.utils.string.trim(str)
assert(trimmed == "test", "Trim falhou")
print("  String.trim: OK")

local escaped = crescent.utils.string.escape_lua_pattern("test.lua")
assert(escaped:find("%."), "Escape falhou")
print("  String.escape_lua_pattern: OK")

-- Path utils
local path = crescent.utils.path.join("/api", "/users")
assert(path == "/api/users", "Path join falhou: " .. path)
print("  Path.join: OK")

local pattern, names = crescent.utils.path.compile("/user/{id}")
assert(pattern ~= nil, "Path compile falhou")
assert(#names == 1, "Path compile não encontrou parâmetro")
assert(names[1] == "id", "Path compile parâmetro incorreto")
print("  Path.compile: OK")

-- Teste 6: Configuração
print("\n✓ Teste 6: Configuração")
app:set("max_body_size", 1024 * 1024)
print("  Configuração definida")

-- Resumo
print("\n" .. string.rep("=", 50))
print("✅ Todos os testes passaram!")
print(string.rep("=", 50))
print("\n💡 Para testar o servidor completo, execute:")
print("   luvit example.lua")
print("\n   Depois teste com curl:")
print("   curl http://localhost:8080/health")
print("   curl http://localhost:8080/")
print("   curl http://localhost:8080/user/123")
