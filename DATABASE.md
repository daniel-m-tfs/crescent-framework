# 💾 Database - Crescent Framework

## 📊 O que está Disponível

### 1. **ORM Completo (ActiveRecord)** ⭐ Recomendado

O Crescent possui um ORM próprio com ActiveRecord pattern:

✅ **CRUD completo** (create, read, update, delete)  
✅ **Validações built-in** (required, min_length, email, unique)  
✅ **Relações** (hasMany, hasOne, belongsTo)  
✅ **Mass assignment protection** (fillable/guarded)  
✅ **Hidden fields** (password nunca é exposto)  
✅ **Timestamps automáticos** (created_at, updated_at)  
✅ **Soft deletes** (opcional, deleted_at)  
✅ **Hooks** (before_save, after_create, etc)  
✅ **Scopes personalizados**  
✅ **Query Builder integrado**  

### 2. **Query Builder (Laravel-style)**

Para queries complexas ou RAW SQL:

✅ **Fluent API** (encadeamento de métodos)  
✅ **WHERE, JOIN, ORDER BY, LIMIT**  
✅ **Execução real** (com driver MySQL)  
✅ **Fallback mock** (desenvolvimento sem DB)  

### 3. **MySQL Driver**

✅ **Connection pooling**  
✅ **Auto-escape** (proteção SQL injection)  
✅ **Fallback automático** para mock  

---

## 🚀 Quick Start com ORM

---

## 🚀 Quick Start com ORM

### 1. Defina seu Model

```lua
-- src/users/models/user.lua
local Model = require("crescent.database.model")

local User = Model:extend({
    table = "users",
    fillable = {"name", "email", "password", "active"},
    hidden = {"password"},
    
    validates = {
        name = {required = true, min_length = 3},
        email = {required = true, email = true, unique = true},
        password = {required = true, min_length = 6}
    },
    
    before_save = function(user)
        -- Hash password antes de salvar
        if user._attributes.password then
            -- user._attributes.password = bcrypt(user._attributes.password)
        end
    end
})

return User
```

### 2. Use o Model

```lua
local User = require("src.users.models.user")

-- CREATE
local user = User:create({
    name = "João Silva",
    email = "joao@example.com",
    password = "secret123",
    active = true
})

-- READ
local user = User:find(1)
local users = User:all()
local active_users = User:where("active", true):get()

-- UPDATE
user:update({name = "João Santos"})
-- ou
user:set("name", "João Santos")
user:save()

-- DELETE
user:delete()

-- TO TABLE (sem campos hidden)
local data = user:toTable() -- { id = 1, name = "João", email = "..." }
```

### 3. Relações

```lua
-- Define relações no model
local User = Model:extend({
    table = "users",
    
    relations = {
        posts = function(self)
            local Post = require("models.post")
            return self:hasMany(Post, "user_id")
        end,
        
        profile = function(self)
            local Profile = require("models.profile")
            return self:hasOne(Profile, "user_id")
        end
    }
})

-- Usa relações
local user = User:find(1)
local posts = user:get("posts") -- Retorna query builder
local profile = user:get("profile") -- Retorna instance ou nil
```

---

## � ORM API Completa

### Model Configuration

```lua
Model:extend({
    table = "users",              -- Nome da tabela
    primary_key = "id",           -- Chave primária (default: "id")
    fillable = {"name", "email"}, -- Campos permitidos em mass assignment
    guarded = {"id", "admin"},    -- Campos protegidos (alternativa a fillable)
    hidden = {"password"},        -- Campos ocultos em toTable()
    timestamps = true,            -- Auto created_at/updated_at (default: true)
    soft_deletes = false,         -- Soft delete com deleted_at (default: false)
    
    -- Validações
    validates = {
        name = {
            required = true,
            min_length = 3,
            max_length = 100
        },
        email = {
            required = true,
            email = true,
            unique = true
        }
    },
    
    -- Hooks
    before_create = function(instance) end,
    after_create = function(instance) end,
    before_save = function(instance) end,
    after_save = function(instance) end,
    before_update = function(instance) end,
    after_update = function(instance) end,
    before_delete = function(instance) end,
    after_delete = function(instance) end,
    
    -- Relações
    relations = {
        posts = function(self)
            return self:hasMany(Post, "user_id")
        end
    }
})
```

### Query Methods (Static)

```lua
-- Buscar
User:find(1)                    -- Busca por ID, retorna instance ou nil
User:findOrFail(1)              -- Busca por ID, error se não encontrar
User:first()                    -- Primeiro registro
User:all()                      -- Todos os registros (array de instances)

-- Query Builder (retorna query builder para encadear)
User:where("active", true)      -- WHERE active = 1
    :where("age", ">=", 18)     -- WHERE age >= 18
    :orderBy("name")            -- ORDER BY name
    :limit(10)                  -- LIMIT 10
    :get()                      -- Executa e retorna array de instances

-- Helpers
User:query()                    -- Retorna query builder raw
```

### Instance Methods

```lua
-- CREATE
local user = User:create({name = "João", email = "joao@example.com"})

-- UPDATE
user:update({name = "João Silva"})
user:set("name", "João Silva")
user:save()

-- DELETE
user:delete()

-- ATTRIBUTES
user:get("name")                -- Retorna atributo
user:set("name", "João")        -- Define atributo
user:toTable()                  -- Retorna tabela (sem hidden fields)

-- VALIDATIONS
local valid, errors = user:validate()
if not valid then
    for field, error in pairs(errors) do
        print(field, error)
    end
end
```

### Relations

```lua
-- Has Many (1:N)
function User:posts()
    return self:hasMany(Post, "user_id", "id")
end

-- Has One (1:1)
function User:profile()
    return self:hasOne(Profile, "user_id", "id")
end

-- Belongs To (N:1)
function Post:user()
    return self:belongsTo(User, "user_id", "id")
end

-- Usando
local user = User:find(1)
local posts = user:get("posts")  -- Array de Post instances
local profile = user:get("profile")  -- Profile instance ou nil
```

### Validations

Regras disponíveis:

```lua
validates = {
    field = {
        required = true,              -- Campo obrigatório
        min_length = 3,               -- Mínimo de caracteres
        max_length = 100,             -- Máximo de caracteres
        email = true,                 -- Validação de email
        unique = true                 -- Único no banco (verifica duplicatas)
    }
}
```

---

### Método Rápido (Recomendado)

```bash
# Execute o script de instalação automática
./install-mysql.sh
```

### Instalação Manual

#### 1. Instale o MySQL (se ainda não tiver)

**macOS:**
```bash
brew install mysql
```

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install mysql-server libmysqlclient-dev
```

**Fedora/RHEL:**
```bash
sudo dnf install mysql-server mysql-devel
```

#### 2. Instale o driver Lua

```bash
luarocks install luasql-mysql
```

#### 3. Configure o .env

```bash
cp .env.example .env
```

Edite o `.env`:
```env
DB_HOST=localhost
DB_PORT=3306
DB_NAME=seu_banco
DB_USER=seu_usuario
DB_PASSWORD=sua_senha
```

#### 4. Teste a conexão

```bash
luvit test-mysql.lua
```

### ⚠️ Sobre Incluir o Driver no Projeto

**Não é possível** incluir `luasql-mysql` diretamente em `/crescent/database/` porque:

1. **É código C compilado** - Precisa ser compilado para cada SO/arquitetura
2. **Depende de bibliotecas nativas** - Requer `libmysqlclient` instalada no sistema
3. **LuaRocks gerencia dependências** - Melhor forma de instalar bibliotecas C

**Bibliotecas Lua puras** (100% Lua) podem ser incluídas, mas drivers de banco raramente são.

## 📝 Uso (Com MySQL Real)

### Exemplo 1: SELECT

```lua
local DB = require("crescent.database.query_builder")

-- Busca usuários ativos
local users = DB.table("users")
    :where("active", true)
    :orderBy("created_at", "DESC")
    :limit(10)
    :get()

-- Resultado: array de tabelas Lua
-- users = {
--   {id = 1, name = "João", email = "joao@example.com", active = 1},
--   {id = 2, name = "Maria", email = "maria@example.com", active = 1},
-- }

for _, user in ipairs(users) do
    print(user.name, user.email)
end
```

### Exemplo 2: INSERT

```lua
-- Insere e retorna o ID
local user_id = DB.table("users"):insert({
    name = "João",
    email = "joao@example.com",
    active = true
})

print("Usuário criado com ID:", user_id)
-- Output: Usuário criado com ID: 5
```

### Exemplo 3: UPDATE

```lua
local result = DB.table("users")
    :where("id", 5)
    :update({ name = "João Silva" })

print("Linhas afetadas:", result.affected)
-- Output: Linhas afetadas: 1
```

### Exemplo 4: DELETE

```lua
local result = DB.table("users")
    :where("active", false)
    :delete()

print("Usuários inativos removidos:", result.affected)
```

### Exemplo 5: JOIN

```lua
local posts = DB.table("posts")
    :select("posts.*", "users.name as author_name")
    :join("users", "posts.user_id", "users.id")
    :where("posts.published", true)
    :get()
```

### Exemplo 6: Em um Service

```lua
-- src/users/services/user.lua
local DB = require("crescent.database.query_builder")

local UserService = {}

function UserService:getAll()
    return DB.table("users")
        :where("active", true)
        :orderBy("name")
        :get()
end

function UserService:getById(id)
    return DB.table("users")
        :where("id", id)
        :first()
end

function UserService:create(data)
    local user_id = DB.table("users"):insert(data)
    return self:getById(user_id)
end

function UserService:update(id, data)
    DB.table("users")
        :where("id", id)
        :update(data)
    return self:getById(id)
end

function UserService:delete(id)
    return DB.table("users")
        :where("id", id)
        :delete()
end

return UserService
```

## 🔧 Modo Fallback (Sem Driver)

Se o `luasql-mysql` não estiver instalado, o framework funciona em **modo mock**:

```lua
local users = DB.table("users"):where("active", true):get()

-- Console output:
-- ⚠️  Driver MySQL não encontrado (luasql-mysql)
--    Execute: luarocks install luasql-mysql
-- ⚠️  [MOCK] SQL: SELECT * FROM users WHERE active = 1

-- Retorna: { note = "Mock result - instale luasql-mysql" }
```

Isso permite desenvolver a aplicação **sem ter MySQL instalado**, e depois integrar o banco quando necessário.

## 🧪 Teste Completo

Execute o arquivo de teste incluído:

```bash
# Certifique-se de ter configurado o .env
luvit test-mysql.lua
```

O teste faz:
1. Testa conexão com MySQL
2. Cria tabela `users` (se não existir)
3. INSERT de um usuário
4. SELECT de usuários ativos
5. UPDATE do usuário
6. COUNT de registros
7. Verifica connection pooling

## 🚀 Roadmap para ORM Completo

Para transformar em um ORM completo, seria necessário:

### 1. Model Base Class
```lua
-- crescent/database/model.lua
local Model = {}

function Model:find(id)
    return DB.table(self.table):where("id", id):first()
end

function Model:create(data)
    return DB.table(self.table):insert(data)
end
```

### 2. Relações
```lua
function User:posts()
    return self:hasMany(Post, "user_id")
end

function Post:user()
    return self:belongsTo(User, "user_id")
end
```

### 3. Migrations
```lua
-- migrations/001_create_users.lua
return {
    up = function()
        return [[
            CREATE TABLE users (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255),
                email VARCHAR(255) UNIQUE,
                created_at TIMESTAMP DEFAULT NOW()
            )
        ]]
    end,
    down = function()
        return "DROP TABLE users"
    end
}
```

## 🎯 Recomendações Atuais

### Para Projetos Simples
Use o Query Builder atual + execute SQL manualmente:

```lua
-- service
function UserService:getAll()
    local sql = DB.table("users"):toSql()
    -- Execute com seu driver de preferência
    local pg = pgmoon.new(config.database)
    pg:connect()
    local users = pg:query(sql)
    pg:keepalive()
    return users
end
```

### Para Projetos Complexos
Considere usar um ORM externo:

1. **[sailor-orm](https://github.com/sailorproject/sailor-orm)** - ORM para Lua
2. **[lapis](https://github.com/leafo/lapis)** - Framework com ORM built-in
3. **Criar seu próprio** - Baseado no Query Builder atual

## 📚 Arquitetura do Database Layer

```
crescent/
└── database/
    ├── mysql.lua           # Driver MySQL com connection pool
    └── query_builder.lua   # Fluent API para construir queries
```

### mysql.lua
- **Connection pooling** (máx 10 conexões simultâneas)
- **Auto-detecção** do driver (luasql-mysql)
- **Fallback para mock** se driver não instalado
- **Escape automático** de valores (proteção SQL injection)
- **UTF-8** configurado automaticamente
- Métodos: `query()`, `select()`, `selectOne()`, `insert()`, `update()`, `delete()`, `test()`

### query_builder.lua
- **Fluent API** (encadeamento de métodos)
- **Gera SQL** otimizado
- **Integrado com mysql.lua** automaticamente
- **Suporte a**: WHERE, OR WHERE, WHERE IN, JOIN, ORDER BY, LIMIT, OFFSET
- Métodos: `table()`, `select()`, `where()`, `join()`, `get()`, `first()`, `insert()`, `update()`, `delete()`

## 🚀 API Completa

### Query Builder Methods

```lua
local DB = require("crescent.database.query_builder")

-- Definir tabela
DB.table("users")

-- SELECT personalizado
  :select("id", "name", "email")
  :select("*")  -- ou tudo

-- WHERE
  :where("active", true)                    -- column, value
  :where("age", ">=", 18)                   -- column, operator, value
  :orWhere("role", "admin")                 -- OR
  :whereIn("status", {"pending", "active"}) -- IN
  :whereNull("deleted_at")                  -- IS NULL
  :whereNotNull("verified_at")              -- IS NOT NULL

-- JOIN
  :join("posts", "users.id", "posts.user_id")
  :leftJoin("profiles", "users.id", "profiles.user_id")

-- ORDER BY
  :orderBy("created_at", "DESC")
  :orderBy("name")  -- ASC por padrão

-- LIMIT / OFFSET
  :limit(10)
  :offset(20)

-- Paginação
  :paginate(page, per_page)  -- Helper

-- Executar
  :get()      -- Array de resultados
  :first()    -- Primeiro resultado (ou nil)
  :count()    -- Conta registros

-- INSERT (retorna ID)
DB.table("users"):insert({
    name = "João",
    email = "joao@example.com"
})

-- UPDATE (retorna { affected = N })
DB.table("users")
    :where("id", 5)
    :update({ name = "Novo Nome" })

-- DELETE (retorna { affected = N })
DB.table("users")
    :where("id", 5)
    :delete()

-- Apenas gerar SQL (sem executar)
local sql = DB.table("users"):where("active", true):toSql()
print(sql)  -- SELECT * FROM users WHERE active = 1
```

### MySQL Methods

```lua
local MySQL = require("crescent.database.mysql")

-- Query raw SQL
local users = MySQL:query("SELECT * FROM users WHERE active = 1")

-- SELECT múltiplos
local users = MySQL:select("SELECT * FROM users WHERE age > ?", {18})

-- SELECT um único
local user = MySQL:selectOne("SELECT * FROM users WHERE id = ?", {5})

-- INSERT (retorna ID)
local user_id = MySQL:insert(
    "INSERT INTO users (name, email) VALUES (?, ?)",
    {"João", "joao@example.com"}
)

-- UPDATE (retorna { affected = N })
local result = MySQL:update(
    "UPDATE users SET name = ? WHERE id = ?",
    {"João Silva", 5}
)

-- DELETE (retorna { affected = N })
local result = MySQL:delete("DELETE FROM users WHERE id = ?", {5})

-- Testar conexão
MySQL.test()

-- Fechar todas conexões
MySQL.closeAll()
```

## ⚠️ Importante

### Segurança
- ✅ **Escape automático** de valores implementado
- ✅ **Proteção contra SQL injection** básica
- ⚠️ **Prepared statements**: luasql-mysql não tem suporte nativo, usamos escape manual
- 🔒 **Recomendação**: Sempre valide dados do usuário antes de inserir

### Performance
- ✅ **Connection pooling** implementado (máx 10 conexões)
- ✅ **Reutilização** de conexões entre requests
- ⚠️ **Limite do pool**: Ajuste `MAX_POOL_SIZE` em `mysql.lua` se necessário
- 💡 **Dica**: Use `MySQL.closeAll()` ao encerrar a aplicação

### Limitações Atuais
- ❌ **Transações**: Não implementadas ainda
- ❌ **Migrações**: Não há sistema de migrations
- ❌ **Validações**: Implemente manualmente ou use biblioteca externa
- ❌ **Relações ORM**: Não há suporte (use JOINs manualmente)

## 🎓 Conclusão

### O que o Crescent Database oferece:

✅ **Query Builder fluente** (Laravel-style)  
✅ **Execução real** de queries MySQL  
✅ **Connection pooling** para performance  
✅ **Fallback para mock** (desenvolvimento sem DB)  
✅ **Escape automático** de valores  
✅ **Fácil integração** com Services/Controllers  
✅ **Driver externo** (luasql-mysql via LuaRocks)  

### O que NÃO é:

❌ **ORM completo** (sem mapeamento de objetos)  
❌ **Sistema de migrations**  
❌ **Validador de models**  
❌ **Suporte a relações** (belongsTo, hasMany)  

### Para usar em produção:

1. ✅ Instale `luasql-mysql`: `./install-mysql.sh`
2. ✅ Configure `.env` com credenciais seguras
3. ✅ Teste conexão: `luvit test-mysql.lua`
4. ✅ Implemente validações nos Services
5. ✅ Configure error handling robusto
6. ⚠️ Considere adicionar transações se necessário
7. ⚠️ Monitore o pool de conexões em produção

### Próximos Passos (Roadmap):

- [ ] Suporte a transações (BEGIN, COMMIT, ROLLBACK)
- [ ] Sistema de migrations
- [ ] Query caching
- [ ] Suporte a PostgreSQL (driver alternativo)
- [ ] ORM completo (opcional, futuro)

---

**Documentação completa em:** [README.md](README.md)  
**Framework:** Crescent v1.0  
**Autor:** Tyne Forge Systems
