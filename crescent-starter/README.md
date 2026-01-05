# 🌙 Crescent Framework

Framework web modular e leve para Luvit.

## 🚀 Quick Start

```bash
# 1. Configure variáveis de ambiente (opcional)
cp .env.example .env
# Edite .env com suas configurações

# 2. Inicie o servidor
luvit app.lua
# ✓ Módulo Hello carregado
# 🌙 Crescent server listening on http://0.0.0.0:8080

# 3. Teste a API
curl http://localhost:8080/hello
curl -X POST http://localhost:8080/hello -H "Content-Type: application/json" -d '{"name":"Test"}'
```

## 📁 Estrutura

```
crescent-starter/
├── app.lua              # Aplicação principal
├── bootstrap.lua        # Bootstrap automático  
├── crescent-cli.lua     # CLI generator
├── crescent/            # Framework core
├── src/hello/           # Exemplo CRUD
└── config/              # Configurações
```

## 🎯 Criar Módulo

```bash
# Gerar módulo completo
luvit crescent-cli.lua make:module User

# Registrar no app.lua
local userModule = require("src.user")
userModule.register(app)
```

**Endpoints automáticos:**
- `GET /user` - Listar
- `GET /user/{id}` - Buscar
- `POST /user` - Criar
- `PUT /user/{id}` - Atualizar
- `DELETE /user/{id}` - Deletar

## 🏗️ Arquitetura

```
Request → Router → Controller → Service → Data
                      ↓
Response ← JSON ←  Controller ← Service
```

### Controller
```lua
function HelloController:index(ctx)
    local service = require("src.hello.services.hello")
    return ctx.json(200, service:getAll())
end
```

### Service
```lua
function HelloService:getAll()
    return { success = true, data = data }
end
```

### Routes
```lua
return function(app, prefix)
    app:get(prefix, function(ctx)
        return controller:index(ctx)
    end)
end
```

## 🛠️ CLI Commands

```bash
luvit crescent-cli.lua help              # Ver comandos
luvit crescent-cli.lua make:module User  # Módulo completo
luvit crescent-cli.lua make:controller   # Controller
luvit crescent-cli.lua make:service      # Service
luvit crescent-cli.lua make:model        # Model
luvit crescent-cli.lua make:routes       # Routes
```

## 📝 Exemplos

```bash
# GET
curl http://localhost:8080/hello

# POST
curl -X POST http://localhost:8080/hello \
  -H "Content-Type: application/json" \
  -d '{"name":"Item"}'

# GET by ID
curl http://localhost:8080/hello/1

# PUT
curl -X PUT http://localhost:8080/hello/1 \
  -H "Content-Type: application/json" \
  -d '{"name":"Updated"}'

# DELETE
curl -X DELETE http://localhost:8080/hello/1
```

## 🎨 Features

- ✅ Roteamento com parâmetros
- ✅ Middleware (CORS, Logger, Security)
- ✅ Context API (`ctx.json()`, `ctx.params`, `ctx.body`)
- ✅ CLI generator
- ✅ Zero configuração

## 🔧 Configuração

### Variáveis de Ambiente (.env)

```bash
# Copie o exemplo
cp .env.example .env

# Edite o arquivo .env
# Configurações sensíveis como senhas de database devem estar aqui!
```

**Exemplo de .env:**
```bash
# Servidor
APP_HOST=0.0.0.0
APP_PORT=8080

# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myapp_db
DB_USER=myapp_user
DB_PASSWORD=secure_password_here

# JWT
JWT_SECRET=your_secret_key_here
```

### Arquivos de Configuração

Edite `config/development.lua` ou `config/production.lua`:

```lua
local env = require("crescent.utils.env")

return {
    server = {
        host = env.get("APP_HOST", "0.0.0.0"),
        port = tonumber(env.get("APP_PORT", "8080"))
    },
    database = {
        host = env.get("DB_HOST", "localhost"),
        password = env.get("DB_PASSWORD") -- Lê do .env
    }
}
```

**⚠️ IMPORTANTE:** 
- Nunca commite o arquivo `.env` (já está no .gitignore)
- Use `.env.example` para documentar variáveis necessárias
- Em produção, sempre use variáveis de ambiente para dados sensíveis

## 🆘 Comandos Úteis

```bash
luvit app.lua              # Iniciar
pkill -f "luvit app"       # Parar
```

## 📦 Requisitos

- [Luvit](https://luvit.io/) v2.18+

## 📄 Licença

MIT

---

**🌙 Crescent Framework** - Web framework for Luvit
