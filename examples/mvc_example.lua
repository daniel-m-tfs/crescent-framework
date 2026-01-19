-- examples/mvc_example.lua
-- Exemplo de uso do padrão MVC com views no Crescent Framework
require("../bootstrap")
local crescent = require("crescent")
local app = crescent.new()

-- =========================================
-- SIMULAÇÃO DE MODELS (dados de exemplo)
-- =========================================

local users_data = {
    {
        id = 1,
        name = "João Silva",
        email = "joao@example.com",
        role = "admin",
        created_at = "2024-01-15"
    },
    {
        id = 2,
        name = "Maria Santos",
        email = "maria@example.com",
        role = "user",
        created_at = "2024-02-20"
    },
    {
        id = 3,
        name = "Pedro Costa",
        email = "pedro@example.com",
        role = "user",
        created_at = "2024-03-10"
    }
}

-- =========================================
-- CONTROLLERS
-- =========================================

-- Controller: Listar todos os usuários
local function list_users_controller(ctx)
    -- Busca dados (normalmente viria do Model/Database)
    local users = users_data
    
    -- Renderiza a view passando os dados
    return ctx.view("views/user_list.etlua", {
        users = users
    })
end

-- Controller: Mostrar perfil de um usuário
local function show_user_controller(ctx)
    local user_id = tonumber(ctx.params.id)
    
    if not user_id then
        return ctx.error(400, "ID de usuário inválido")
    end
    
    -- Busca usuário (normalmente viria do Model/Database)
    local user = nil
    for _, u in ipairs(users_data) do
        if u.id == user_id then
            user = u
            break
        end
    end
    
    if not user then
        return ctx.error(404, "Usuário não encontrado")
    end
    
    -- Renderiza a view passando os dados do usuário
    return ctx.view("views/user_profile.etlua", user)
end

-- Controller: Página inicial com exemplo de HTML inline
local function home_controller(ctx)
    local html = [[
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Crescent MVC Example</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 800px;
                margin: 50px auto;
                padding: 20px;
                background-color: #f5f5f5;
            }
            .card {
                background: white;
                padding: 30px;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            h1 {
                color: #4CAF50;
            }
            a {
                display: inline-block;
                margin: 10px 0;
                padding: 10px 20px;
                background-color: #4CAF50;
                color: white;
                text-decoration: none;
                border-radius: 4px;
            }
            a:hover {
                background-color: #45a049;
            }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>🌙 Crescent Framework - MVC Example</h1>
            <p>Bem-vindo ao exemplo de MVC com templates!</p>
            <h3>Rotas disponíveis:</h3>
            <div>
                <a href="/users">📋 Ver todos os usuários</a>
            </div>
            <div>
                <a href="/users/1">👤 Ver usuário #1</a>
            </div>
            <div>
                <a href="/users/2">👤 Ver usuário #2</a>
            </div>
            <div>
                <a href="/users/3">👤 Ver usuário #3</a>
            </div>
        </div>
    </body>
    </html>
        ]]
    
    return ctx.html(200, html)
end

-- =========================================
-- ROTAS
-- =========================================

app:get("/", home_controller)
app:get("/users", list_users_controller)
app:get("/users/{id}", show_user_controller)

-- =========================================
-- INICIAR SERVIDOR
-- =========================================

print("🌙 Crescent MVC Example")
print("📝 Servidor rodando em http://localhost:3000")
print("")
print("Rotas disponíveis:")
print("  GET  /            - Página inicial")
print("  GET  /users       - Lista de usuários")
print("  GET  /users/:id   - Perfil do usuário")
print("")

app:listen(3000)
