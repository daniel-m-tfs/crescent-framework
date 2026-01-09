# Segurança - Crescent Framework

## Proteção contra SQL Injection

O Crescent Framework implementa várias camadas de proteção contra SQL Injection:

### 1. QueryBuilder - Escape Automático

O QueryBuilder escapa automaticamente todos os valores em queries:

```lua
-- ✅ SEGURO - Valores são escapados automaticamente
User:query()
    :where("name", user_input)
    :where("age", ">", age_input)
    :get()
```

**Proteções implementadas:**
- Escape de aspas simples (`'` → `''`)
- Escape de backslashes (`\` → `\\`)
- Remoção de caracteres nulos (`\0`)
- Validação de números (NaN check)
- Conversão segura de tipos

### 2. Validação de Identificadores

Nomes de tabelas e colunas são validados para prevenir injection:

```lua
-- ✅ SEGURO - Apenas caracteres permitidos: a-z, A-Z, 0-9, _, .
QB.table("users")
QB.table("company.users")  -- Com schema

-- ❌ ERRO - Caracteres inválidos são rejeitados
QB.table("users; DROP TABLE users--")  -- Lança erro
```

### 3. Queries Raw com Bindings (Recomendado)

Para queries customizadas, **SEMPRE** use bindings com placeholders `?`:

```lua
-- ✅ SEGURO - Usa bindings
local results = User:raw(
    "SELECT * FROM users WHERE name = ? AND age > ?",
    {user_input, age_input}
)

-- ✅ SEGURO - Query complexa com bindings
local stats = User:raw([[
    SELECT 
        DATE(created_at) as date,
        COUNT(*) as total
    FROM users
    WHERE created_at > ? AND status = ?
    GROUP BY DATE(created_at)
]], {"2026-01-01", "active"})
```

### 4. O QUE EVITAR

```lua
-- ❌ PERIGOSO - Concatenação de strings sem escape
local sql = "SELECT * FROM users WHERE name = '" .. user_input .. "'"
User:raw(sql)  -- VULNERÁVEL a SQL Injection!

-- ❌ PERIGOSO - Interpolação direta
local sql = string.format("SELECT * FROM users WHERE id = %s", user_input)
User:raw(sql)  -- VULNERÁVEL!
```

## Níveis de Proteção

### Nível 1: QueryBuilder (Recomendado para 90% dos casos)
```lua
-- Proteção automática completa
User:query()
    :where("email", user_email)
    :where("status", "active")
    :get()
```

### Nível 2: Raw Queries com Bindings (Para queries complexas)
```lua
-- Proteção via escape de bindings
User:raw("SELECT * FROM users WHERE email = ?", {user_email})
```

### Nível 3: Raw Queries sem Bindings (APENAS para queries fixas)
```lua
-- Use SOMENTE quando não há inputs do usuário
User:raw("SELECT COUNT(*) as total FROM users")
User:raw("SHOW TABLES")
```

## Outras Proteções de Segurança

### Mass Assignment Protection

Use `fillable` ou `guarded` para proteger campos sensíveis:

```lua
local User = Model:extend({
    fillable = {"name", "email"},  -- Apenas esses campos podem ser atribuídos
    -- OU
    guarded = {"id", "is_admin"},  -- Esses campos NÃO podem ser atribuídos
})

-- ✅ SEGURO - Mesmo que user_input contenha "is_admin", será ignorado
User:create(user_input)
```

### Hidden Fields

Oculte campos sensíveis nas respostas JSON:

```lua
local User = Model:extend({
    hidden = {"password", "remember_token", "api_key"}
})

local user = User:find(1)
local json = user:toArray()
-- password NÃO aparece no JSON
```

### Validações

Valide inputs antes de salvar:

```lua
local User = Model:extend({
    validates = {
        email = {
            required = true,
            email = true,  -- Valida formato de e-mail
            max_length = 255
        },
        age = {
            numeric = true,
            min = 0,
            max = 150
        }
    }
})
```

## Limitações Conhecidas

⚠️ **IMPORTANTE**: O escape implementado é uma camada básica de proteção. Para aplicações em produção com dados sensíveis, recomendamos:

1. **Usar prepared statements nativos do driver MySQL** quando disponível
2. **Validar TODOS os inputs do usuário** antes de usar nas queries
3. **Limitar permissões do usuário do banco de dados** (princípio do menor privilégio)
4. **Usar HTTPS/TLS** para conexões com o banco
5. **Fazer auditorias de segurança regulares**

## Checklist de Segurança

- [ ] Usar QueryBuilder sempre que possível
- [ ] Queries raw SEMPRE com bindings (exceto queries fixas)
- [ ] Validar inputs do usuário
- [ ] Configurar `fillable` ou `guarded` nos Models
- [ ] Configurar `hidden` para campos sensíveis
- [ ] Limitar permissões do usuário do banco
- [ ] Usar HTTPS em produção
- [ ] Fazer backup regular do banco
- [ ] Monitorar logs de queries suspeitas

## Reportando Vulnerabilidades

Se você encontrar uma vulnerabilidade de segurança, por favor **NÃO** abra uma issue pública. Entre em contato diretamente com os mantenedores.
