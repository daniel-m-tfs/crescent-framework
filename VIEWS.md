# Views e Templates - Crescent Framework

O Crescent Framework suporta templates usando o **etlua** (Embedded Lua templates), permitindo criar aplicações no padrão MVC (Model-View-Controller).

## 📖 Índice

- [Sintaxe de Templates](#sintaxe-de-templates)
- [Usando Views nos Controllers](#usando-views-nos-controllers)
- [Métodos Disponíveis](#métodos-disponíveis)
- [Exemplos Práticos](#exemplos-práticos)
- [Organização de Arquivos](#organização-de-arquivos)

---

## Sintaxe de Templates

Os templates etlua usam tags especiais para inserir código Lua no HTML:

### Tags Básicas

- **`<% código %>`** - Executa código Lua (sem output)
- **`<%= variável %>`** - Exibe valor (com escape HTML automático)
- **`<%- variável %>`** - Exibe valor (SEM escape HTML)
- **`<% código -%>`** - Remove quebra de linha após a tag

### Exemplos de Sintaxe

```html
<!-- Variáveis -->
<h1>Olá, <%= name %>!</h1>

<!-- Condicionais -->
<% if user.admin then %>
    <p>Você é um administrador</p>
<% else %>
    <p>Você é um usuário comum</p>
<% end %>

<!-- Loops -->
<ul>
<% for i, item in ipairs(items) do %>
    <li><%= item.name %></li>
<% end %>
</ul>

<!-- Expressões Lua -->
<p>Total: <%= price * quantity %></p>
<p>Data: <%= os.date("%d/%m/%Y") %></p>
```

---

## Usando Views nos Controllers

O Crescent fornece métodos simples para renderizar views nos controllers:

### Método `ctx.view()`

```lua
ctx.view(view_path, data, status, extra_headers)
```

**Parâmetros:**
- `view_path` (string, obrigatório) - Caminho para o arquivo template
- `data` (table, opcional) - Dados a serem passados para a view
- `status` (number, opcional) - Status HTTP (padrão: 200)
- `extra_headers` (table, opcional) - Headers HTTP adicionais

**Exemplo:**

```lua
local function show_user(ctx)
    local user = {
        name = "João Silva",
        email = "joao@example.com",
        role = "admin"
    }
    
    return ctx.view("views/user.etlua", user)
end
```

### Método `response.view()`

Também disponível no módulo de resposta:

```lua
local response = require("crescent.core.response")

response.view(res, status, view_path, data, extra_headers)
```

---

## Métodos Disponíveis

### 1. `etlua.render(template_string, data)`

Renderiza uma string de template com dados:

```lua
local etlua = require("crescent.utils.etlua")

local template = "Olá, <%= name %>!"
local html = etlua.render(template, { name = "Maria" })
-- Resultado: "Olá, Maria!"
```

### 2. `etlua.render_file(file_path, data)`

Renderiza um arquivo de template:

```lua
local etlua = require("crescent.utils.etlua")

local html, err = etlua.render_file("views/home.etlua", {
    title = "Página Inicial",
    users = users_list
})

if not html then
    print("Erro: " .. err)
end
```

### 3. `etlua.compile(template_string)`

Compila um template para reutilização:

```lua
local etlua = require("crescent.utils.etlua")

-- Compila o template uma vez
local template_fn = etlua.compile("Olá, <%= name %>!")

-- Reutiliza várias vezes
local html1 = template_fn({ name = "João" })
local html2 = template_fn({ name = "Maria" })
```

---

## Exemplos Práticos

### Exemplo 1: Perfil de Usuário

**Controller:**
```lua
local function show_profile(ctx)
    local user_id = tonumber(ctx.params.id)
    
    -- Busca usuário no banco (exemplo simplificado)
    local user = User:find(user_id)
    
    if not user then
        return ctx.error(404, "Usuário não encontrado")
    end
    
    -- Renderiza view com dados do usuário
    return ctx.view("views/profile.etlua", {
        name = user.name,
        email = user.email,
        role = user.role,
        created_at = user.created_at
    })
end
```

**View (views/profile.etlua):**
```html
<!DOCTYPE html>
<html>
<head>
    <title>Perfil - <%= name %></title>
</head>
<body>
    <h1><%= name %></h1>
    <p>Email: <%= email %></p>
    <% if role then %>
        <p>Função: <%= role %></p>
    <% end %>
    <p>Membro desde: <%= created_at %></p>
</body>
</html>
```

### Exemplo 2: Lista de Itens

**Controller:**
```lua
local function list_products(ctx)
    -- Busca produtos
    local products = Product:all()
    
    return ctx.view("views/products.etlua", {
        products = products,
        total = #products
    })
end
```

**View (views/products.etlua):**
```html
<!DOCTYPE html>
<html>
<head>
    <title>Produtos</title>
</head>
<body>
    <h1>Lista de Produtos (<%= total %>)</h1>
    
    <% if total > 0 then %>
        <table>
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Nome</th>
                    <th>Preço</th>
                </tr>
            </thead>
            <tbody>
                <% for i, product in ipairs(products) do %>
                <tr>
                    <td><%= product.id %></td>
                    <td><%= product.name %></td>
                    <td>R$ <%= string.format("%.2f", product.price) %></td>
                </tr>
                <% end %>
            </tbody>
        </table>
    <% else %>
        <p>Nenhum produto encontrado.</p>
    <% end %>
</body>
</html>
```

### Exemplo 3: Formulário com Dados

**Controller:**
```lua
local function edit_user(ctx)
    local user_id = tonumber(ctx.params.id)
    local user = User:find(user_id)
    
    if not user then
        return ctx.error(404, "Usuário não encontrado")
    end
    
    return ctx.view("views/edit_user.etlua", {
        user = user,
        csrf_token = generate_csrf_token(ctx)
    })
end
```

**View (views/edit_user.etlua):**
```html
<!DOCTYPE html>
<html>
<head>
    <title>Editar Usuário</title>
</head>
<body>
    <h1>Editar <%= user.name %></h1>
    
    <form method="POST" action="/users/<%= user.id %>">
        <input type="hidden" name="_token" value="<%= csrf_token %>">
        
        <label>Nome:</label>
        <input type="text" name="name" value="<%= user.name %>" required>
        
        <label>Email:</label>
        <input type="email" name="email" value="<%= user.email %>" required>
        
        <label>Função:</label>
        <select name="role">
            <option value="user" <% if user.role == "user" then %>selected<% end %>>Usuário</option>
            <option value="admin" <% if user.role == "admin" then %>selected<% end %>>Admin</option>
        </select>
        
        <button type="submit">Salvar</button>
    </form>
</body>
</html>
```

---

## Organização de Arquivos

Recomendamos organizar as views em uma estrutura lógica:

```
seu-projeto/
├── app.lua
├── views/
│   ├── layouts/
│   │   └── main.etlua          # Layout principal
│   ├── users/
│   │   ├── list.etlua          # Lista de usuários
│   │   ├── show.etlua          # Detalhes do usuário
│   │   ├── edit.etlua          # Editar usuário
│   │   └── new.etlua           # Novo usuário
│   ├── products/
│   │   ├── list.etlua
│   │   └── show.etlua
│   └── partials/
│       ├── header.etlua        # Cabeçalho reutilizável
│       └── footer.etlua        # Rodapé reutilizável
└── src/
    └── users/
        └── controllers/
            └── users.lua
```

### Usando Partials (Incluindo Templates)

Você pode incluir outros templates usando `require` ou lendo arquivos:

```lua
-- No template principal
<% 
    local etlua = require("crescent.utils.etlua")
    local header = etlua.render_file("views/partials/header.etlua", {
        title = "Minha Página"
    })
%>
<%- header %>

<!-- Conteúdo principal -->
<h1>Conteúdo da Página</h1>

<% 
    local footer = etlua.render_file("views/partials/footer.etlua", {})
%>
<%- footer %>
```

---

## Dicas e Boas Práticas

1. **Use `<%= %>` por padrão** - Protege contra XSS com escape automático
2. **Use `<%- %>` apenas para HTML confiável** - Quando você tem certeza que o conteúdo é seguro
3. **Separe lógica do controller** - Views devem apenas exibir dados
4. **Crie componentes reutilizáveis** - Use partials para headers, footers, etc.
5. **Valide dados no controller** - Não confie em validação apenas na view
6. **Use layouts** - Evite duplicação de HTML comum

---

## Tratamento de Erros

Se houver erro ao renderizar um template, você receberá um erro 500 automaticamente:

```lua
local function my_controller(ctx)
    -- Se o template tiver erro, retorna 500 automaticamente
    return ctx.view("views/invalid.etlua", data)
end
```

Para tratamento customizado:

```lua
local etlua = require("crescent.utils.etlua")

local function my_controller(ctx)
    local html, err = etlua.render_file("views/my_view.etlua", data)
    
    if not html then
        -- Log do erro
        print("Erro ao renderizar template: " .. err)
        
        -- Retorna página de erro customizada
        return ctx.html(500, "<h1>Erro ao carregar página</h1>")
    end
    
    return ctx.html(200, html)
end
```

---

## Passando Dados para Views

Você pode passar qualquer tipo de dado Lua para as views:

```lua
return ctx.view("views/dashboard.etlua", {
    -- Strings
    title = "Dashboard",
    
    -- Números
    user_count = 150,
    
    -- Booleanos
    is_admin = true,
    
    -- Arrays
    users = { user1, user2, user3 },
    
    -- Objetos/Tables
    stats = {
        total = 1000,
        active = 850,
        inactive = 150
    },
    
    -- Funções
    format_date = function(timestamp)
        return os.date("%d/%m/%Y", timestamp)
    end
})
```

Usando na view:

```html
<h1><%= title %></h1>
<p>Total de usuários: <%= user_count %></p>

<% if is_admin then %>
    <p>Você tem acesso administrativo</p>
<% end %>

<p>Ativo: <%= stats.active %> | Inativo: <%= stats.inactive %></p>

<p>Data: <%= format_date(os.time()) %></p>
```

---

## Referências

- [Documentação etlua](https://github.com/leafo/etlua)
- [Lua Pattern Matching](http://lua-users.org/wiki/PatternsTutorial)
- [Crescent Framework](README.md)
