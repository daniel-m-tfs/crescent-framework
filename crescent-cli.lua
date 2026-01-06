#!/usr/bin/env luvit
-- crescent-cli
-- CLI para geração de código no estilo Artisan/NestJS

local fs = require('fs')
local path = require('path')

-- Cores para output
local colors = {
    reset = "\27[0m",
    green = "\27[32m",
    blue = "\27[34m",
    yellow = "\27[33m",
    red = "\27[31m",
    bold = "\27[1m"
}

local function print_success(msg)
    print(colors.green .. "✓ " .. msg .. colors.reset)
end

local function print_info(msg)
    print(colors.blue .. "ℹ " .. msg .. colors.reset)
end

local function print_error(msg)
    print(colors.red .. "✗ " .. msg .. colors.reset)
end

local function print_header(msg)
    print(colors.bold .. colors.blue .. "\n🌙 " .. msg .. colors.reset .. "\n")
end

-- Capitaliza primeira letra
local function capitalize(str)
    return str:gsub("^%l", string.upper)
end

-- Converte para snake_case
local function to_snake_case(str)
    return str:gsub("(%u)", "_%1"):lower():gsub("^_", "")
end

-- Cria diretório se não existir
local function ensure_dir(dir)
    local cmd = string.format('mkdir -p "%s"', dir)
    os.execute(cmd)
end

-- Escreve arquivo
local function write_file(filepath, content)
    local file = io.open(filepath, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

-- Templates
local templates = {}

templates.migration = function(name)
    local timestamp = os.date("%Y%m%d%H%M%S")
    local filename = timestamp .. "_" .. name .. ".lua"
    
    -- Extrai nome da tabela do padrão create_xxx_table ou add_xxx_to_yyy
    local table_name = "example"
    
    -- Padrão: create_products_table -> products
    if name:match("^create_(.+)_table$") then
        table_name = name:match("^create_(.+)_table$")
    -- Padrão: add_column_to_users -> users
    elseif name:match("_to_(.+)$") then
        table_name = name:match("_to_(.+)$")
    -- Padrão: drop_products_table -> products
    elseif name:match("^drop_(.+)_table$") then
        table_name = name:match("^drop_(.+)_table$")
    -- Padrão: update_products_table -> products
    elseif name:match("^update_(.+)_table$") then
        table_name = name:match("^update_(.+)_table$")
    end
    
    local content = [[-- migrations/]] .. filename .. "\n" .. [[
-- Migration: ]] .. name .. "\n\n" .. [[
local Migration = {}

-- Executa a migration (criar tabelas, adicionar colunas, etc)
function Migration:up()
    return ]].. "[[" .. [[

        CREATE TABLE IF NOT EXISTS ]] .. table_name .. [[ (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]] .. "]]" .. [[

end

-- Desfaz a migration (remover tabelas, colunas, etc)
function Migration:down()
    return ]] .. "[[" .. [[

        DROP TABLE IF EXISTS ]] .. table_name .. [[;
    ]] .. "]]" .. [[

end

return Migration
]]
    
    return filename, content
end

templates.controller = function(name, module_name)
    local class_name = capitalize(name) .. "Controller"
    local service_name = to_snake_case(name)
    return string.format([[-- src/%s/controllers/%s.lua
-- Controller para %s

local service = require("src.%s.services.%s")
local %s = {}

function %s:index(ctx)
    local result = service:getAll()
    return ctx.json(200, result)
end

function %s:show(ctx)
    local id = ctx.params.id
    local result = service:getById(id)
    
    if result then
        return ctx.json(200, result)
    else
        return ctx.json(404, { error = "Not found" })
    end
end

function %s:create(ctx)
    local body = ctx.body or {}
    local result = service:create(body)
    return ctx.json(201, result)
end

function %s:update(ctx)
    local id = ctx.params.id
    local body = ctx.body or {}
    local result = service:update(id, body)
    
    if result then
        return ctx.json(200, result)
    else
        return ctx.json(404, { error = "Not found" })
    end
end

function %s:delete(ctx)
    local id = ctx.params.id
    local success = service:delete(id)
    
    if success then
        return ctx.no_content()
    else
        return ctx.json(404, { error = "Not found" })
    end
end

return %s
]], module_name, service_name, name, 
    module_name, service_name, class_name,
    class_name, class_name, class_name, class_name, class_name, class_name)
end

templates.service = function(name, module_name)
    local class_name = capitalize(name) .. "Service"
    return string.format([[-- src/%s/services/%s.lua
-- Service para lógica de negócio de %s

local %s = {}

-- Simulação de banco de dados (substitua por ORM real)
local data = {}
local next_id = 1

function %s:getAll()
    return {
        success = true,
        data = data,
        message = "Lista de %s"
    }
end

function %s:getById(id)
    local search_id = tonumber(id) or id
    for _, item in ipairs(data) do
        if item.id == search_id then
            return {
                success = true,
                data = item
            }
        end
    end
    return nil
end

function %s:create(body)
    local item = {
        id = next_id,
        created_at = os.time()
    }
    
    -- Copia dados do body
    for k, v in pairs(body) do
        item[k] = v
    end
    
    table.insert(data, item)
    next_id = next_id + 1
    
    return {
        success = true,
        data = item,
        message = "%s criado com sucesso"
    }
end

function %s:update(id, body)
    local search_id = tonumber(id) or id
    for i, item in ipairs(data) do
        if item.id == search_id then
            for k, v in pairs(body) do
                item[k] = v
            end
            item.updated_at = os.time()
            return {
                success = true,
                data = item,
                message = "%s atualizado"
            }
        end
    end
    return nil
end

function %s:delete(id)
    local search_id = tonumber(id) or id
    for i, item in ipairs(data) do
        if item.id == search_id then
            table.remove(data, i)
            return true
        end
    end
    return false
end

return %s
]], module_name, to_snake_case(name), name,
    class_name, class_name, name, class_name,
    class_name, name, class_name, name, class_name, class_name)
end

templates.model = function(name, module_name)
    local class_name = capitalize(name)
    local table_name = to_snake_case(name)
    return string.format([[-- src/%s/models/%s.lua
-- Model para %s usando Active Record ORM

local Model = require("crescent.database.model")

local %s = Model:extend({
    table = "%s",
    primary_key = "id",
    timestamps = true,
    soft_deletes = false,
    
    fillable = {
        -- Adicione aqui os campos que podem ser preenchidos em massa
        -- "name", "email", etc.
    },
    
    hidden = {
        -- Campos que não devem aparecer em JSON/serialização
        -- "password", "token", etc.
    },
    
    validates = {
        -- Adicione validações aqui
        -- name = {required = true, min = 3, max = 255},
        -- email = {required = true, email = true, unique = true},
    },
    
    relations = {
        -- Defina relações aqui
        -- posts = {type = "hasMany", model = "Post", foreign_key = "user_id"},
        -- profile = {type = "hasOne", model = "Profile", foreign_key = "user_id"},
    }
})

-- Métodos personalizados do model
-- function %s:customMethod()
--     -- Seu código aqui
-- end

return %s
]], module_name, table_name, class_name,
    class_name, table_name, class_name, class_name)
end

templates.routes = function(name, module_name)
    return string.format([[-- src/%s/routes/%s.lua
-- Rotas para %s

local controller = require("src.%s.controllers.%s")

return function(app, prefix)
    prefix = prefix or "/%s"
    
    -- CRUD completo
    app:get(prefix, function(ctx)
        return controller:index(ctx)
    end)
    
    app:get(prefix .. "/{id}", function(ctx)
        return controller:show(ctx)
    end)
    
    app:post(prefix, function(ctx)
        return controller:create(ctx)
    end)
    
    app:put(prefix .. "/{id}", function(ctx)
        return controller:update(ctx)
    end)
    
    app:delete(prefix .. "/{id}", function(ctx)
        return controller:delete(ctx)
    end)
end
]], module_name, to_snake_case(name), name,
    module_name, to_snake_case(name), to_snake_case(name))
end

templates.module = function(name)
    local module_name = to_snake_case(name)
    return string.format([[-- src/%s/init.lua
-- Módulo %s - Agrupa controllers, services e rotas

local Module = {}

function Module.register(app)
    -- Registra rotas do módulo
    local routes = require("src.%s.routes.%s")
    routes(app, "/%s")
    
    print("✓ Módulo %s carregado")
end

return Module
]], module_name, capitalize(name),
    module_name, to_snake_case(name), to_snake_case(name), capitalize(name))
end

-- Comandos
local commands = {}

commands.make = {}

commands.make.controller = function(name, module_name)
    module_name = module_name or to_snake_case(name)
    local dir = string.format("src/%s/controllers", module_name)
    ensure_dir(dir)
    
    local filepath = string.format("%s/%s.lua", dir, to_snake_case(name))
    local content = templates.controller(name, module_name)
    
    if write_file(filepath, content) then
        print_success("Controller criado: " .. filepath)
    else
        print_error("Erro ao criar controller")
    end
end

commands.make.service = function(name, module_name)
    module_name = module_name or to_snake_case(name)
    local dir = string.format("src/%s/services", module_name)
    ensure_dir(dir)
    
    local filepath = string.format("%s/%s.lua", dir, to_snake_case(name))
    local content = templates.service(name, module_name)
    
    if write_file(filepath, content) then
        print_success("Service criado: " .. filepath)
    else
        print_error("Erro ao criar service")
    end
end

commands.make.model = function(name, module_name)
    module_name = module_name or to_snake_case(name)
    local dir = string.format("src/%s/models", module_name)
    ensure_dir(dir)
    
    local filepath = string.format("%s/%s.lua", dir, to_snake_case(name))
    local content = templates.model(name, module_name)
    
    if write_file(filepath, content) then
        print_success("Model criado: " .. filepath)
    else
        print_error("Erro ao criar model")
    end
end

commands.make.routes = function(name, module_name)
    module_name = module_name or to_snake_case(name)
    local dir = string.format("src/%s/routes", module_name)
    ensure_dir(dir)
    
    local filepath = string.format("%s/%s.lua", dir, to_snake_case(name))
    local content = templates.routes(name, module_name)
    
    if write_file(filepath, content) then
        print_success("Routes criadas: " .. filepath)
    else
        print_error("Erro ao criar routes")
    end
end

commands.make.module = function(name)
    local module_name = to_snake_case(name)
    local dir = string.format("src/%s", module_name)
    ensure_dir(dir)
    
    -- Cria todas as estruturas
    print_header("Criando módulo " .. capitalize(name))
    
    commands.make.controller(name, module_name)
    commands.make.service(name, module_name)
    commands.make.model(name, module_name)
    commands.make.routes(name, module_name)
    
    -- Cria arquivo do módulo (init.lua)
    local filepath = string.format("src/%s/init.lua", module_name)
    local content = templates.module(name)
    
    if write_file(filepath, content) then
        print_success("Módulo criado: " .. filepath)
    end
    
    print_info("\nPara usar o módulo, adicione no app.lua:")
    print(colors.yellow .. string.format([[
local %sModule = require("src.%s")
%sModule.register(app)
]], module_name, module_name, module_name) .. colors.reset)
end

-- Migration commands
commands.make.migration = function(name)
    ensure_dir("migrations")
    
    local filename, content = templates.migration(name)
    local filepath = "migrations/" .. filename
    
    if write_file(filepath, content) then
        print_success("Migration criada: " .. filepath)
        print_info("\nEdite o arquivo e implemente os métodos up() e down()")
        print_info("Depois execute: luvit crescent-cli migrate")
    else
        print_error("Erro ao criar migration")
    end
end

-- Migration commands
commands.migrate = function()
    local handle = io.popen("luvit crescent/database/migrate.lua migrate 2>&1")
    if handle then
        local output = handle:read("*a")
        handle:close()
        print(output)
    end
end

commands.migrate_rollback = function()
    local handle = io.popen("luvit crescent/database/migrate.lua rollback 2>&1")
    if handle then
        local output = handle:read("*a")
        handle:close()
        print(output)
    end
end

commands.migrate_status = function()
    local handle = io.popen("luvit crescent/database/migrate.lua status 2>&1")
    if handle then
        local output = handle:read("*a")
        handle:close()
        print(output)
    end
end

-- Command: new project
commands.new = function(project_name)
    if not project_name or project_name == "" then
        print_error("Nome do projeto é obrigatório!")
        print_info("Uso: crescent new <nome-do-projeto>")
        return
    end
    
    print_header("Criando novo projeto Crescent: " .. project_name)
    
    -- Verifica se diretório já existe
    local check_cmd = string.format('test -d "%s"', project_name)
    local exists = os.execute(check_cmd) == 0
    
    if exists then
        print_error("Diretório '" .. project_name .. "' já existe!")
        return
    end
    
    -- Cria estrutura de diretórios
    print_info("Criando estrutura de diretórios...")
    local dirs = {
        project_name,
        project_name .. "/src",
        project_name .. "/config",
        project_name .. "/migrations",
        project_name .. "/public",
        project_name .. "/tests"
    }
    
    for _, dir in ipairs(dirs) do
        ensure_dir(dir)
    end
    
    -- Cria app.lua
    local app_content = [[#!/usr/bin/env luvit
-- app.lua
-- Ponto de entrada da aplicação

local Crescent = require('crescent')
local env = require('config.development')

-- Cria aplicação
local app = Crescent.new(env)

-- Middleware
app:use(require('crescent.middleware.logger'))
app:use(require('crescent.middleware.cors'))

-- Rotas básicas
app:get('/', function(ctx)
    return ctx.json(200, {
        message = "Welcome to Crescent Framework!",
        version = "1.0.0",
        docs = "https://crescent.tyne.com.br"
    })
end)

app:get('/health', function(ctx)
    return ctx.json(200, { status = "ok" })
end)

-- Exemplo de CRUD (descomente para usar)
-- local usersModule = require("src.users")
-- usersModule.register(app)

-- Inicia servidor
app:listen()
]]
    
    write_file(project_name .. "/app.lua", app_content)
    print_success("Criado: app.lua")
    
    -- Cria .env.example
    local env_content = [[# Database Configuration
DB_HOST=localhost
DB_PORT=3306
DB_NAME=crescent_db
DB_USER=root
DB_PASSWORD=

# Server Configuration
PORT=3000
HOST=0.0.0.0
]]
    
    write_file(project_name .. "/.env.example", env_content)
    print_success("Criado: .env.example")
    
    -- Cria config/development.lua
    local config_content = [[-- config/development.lua
return {
    port = tonumber(os.getenv("PORT")) or 3000,
    host = os.getenv("HOST") or "0.0.0.0",
    env = "development",
    debug = true,
    
    database = {
        driver = "mysql",
        host = os.getenv("DB_HOST") or "localhost",
        port = tonumber(os.getenv("DB_PORT")) or 3306,
        database = os.getenv("DB_NAME") or "crescent_db",
        user = os.getenv("DB_USER") or "root",
        password = os.getenv("DB_PASSWORD") or "",
    }
}
]]
    
    write_file(project_name .. "/config/development.lua", config_content)
    print_success("Criado: config/development.lua")
    
    -- Cria .gitignore
    local gitignore_content = [[.env
node_modules/
*.log
.DS_Store
]]
    
    write_file(project_name .. "/.gitignore", gitignore_content)
    print_success("Criado: .gitignore")
    
    -- Cria README.md
    local readme_content = string.format([[# %s

Projeto criado com Crescent Framework

## Instalação

```bash
# Copie o arquivo de ambiente
cp .env.example .env

# Edite as configurações
nano .env

# Instale as dependências (se necessário)
luarocks install crescent
```

## Executar

```bash
luvit app.lua
```

## Gerar código

```bash
# Criar um módulo completo
luvit crescent-cli make:module User

# Criar controller
luvit crescent-cli make:controller Product

# Criar migration
luvit crescent-cli make:migration create_products_table
```

## Documentação

https://crescent.tyne.com.br
]], project_name)
    
    write_file(project_name .. "/README.md", readme_content)
    print_success("Criado: README.md")
    
    -- Mensagem final
    print_success("\n✨ Projeto criado com sucesso!")
    print_info("\nPróximos passos:")
    print(colors.yellow .. string.format([[
  cd %s
  cp .env.example .env
  nano .env
  luvit app.lua
]], project_name) .. colors.reset)
    
    print_info("\nPara criar um módulo CRUD completo:")
    print(colors.yellow .. string.format([[
  cd %s
  luvit crescent-cli make:module User
]], project_name) .. colors.reset)
end

-- Help
local function show_help()
    print_header("Crescent CLI - Gerador de Código")
    print([[
Uso: luvit crescent-cli <comando> [opções]

Comandos disponíveis:

  new <nome>                        Cria um novo projeto Crescent
  make:controller <nome> [módulo]   Cria um controller
  make:service <nome> [módulo]      Cria um service
  make:model <nome> [módulo]        Cria um model
  make:routes <nome> [módulo]       Cria arquivo de rotas
  make:module <nome>                Cria um módulo completo (CRUD)
  make:migration <nome>             Cria uma migration
  migrate                           Executa migrations pendentes
  migrate:rollback                  Desfaz última migration
  migrate:status                    Mostra status das migrations

Exemplos:

  luvit crescent-cli new meu-projeto
  luvit crescent-cli make:module User
  luvit crescent-cli make:controller Product
  luvit crescent-cli make:service Auth auth
  luvit crescent-cli make:migration create_products_table
  luvit crescent-cli migrate
    ]])
end

-- Main
local function main(args)
    if #args == 0 then
        show_help()
        return
    end
    
    local command = args[1]
    local name = args[2]
    local module_name = args[3]
    
    if command == "new" and name then
        commands.new(name)
    elseif command == "make:controller" and name then
        commands.make.controller(name, module_name)
    elseif command == "make:service" and name then
        commands.make.service(name, module_name)
    elseif command == "make:model" and name then
        commands.make.model(name, module_name)
    elseif command == "make:routes" and name then
        commands.make.routes(name, module_name)
    elseif command == "make:module" and name then
        commands.make.module(name)
    elseif command == "make:migration" and name then
        commands.make.migration(name)
    elseif command == "migrate" then
        commands.migrate()
    elseif command == "migrate:rollback" then
        commands.migrate_rollback()
    elseif command == "migrate:status" then
        commands.migrate_status()
    else
        show_help()
    end
end

-- Pega argumentos do process
if _G.process and _G.process.argv then
    local args = {}
    local found_script = false
    
    -- Encontra onde está o script e pega os args depois dele
    for i, v in ipairs(_G.process.argv) do
        if found_script then
            table.insert(args, v)
        elseif v:match("crescent%-cli%.lua$") then
            found_script = true
        end
    end
    
    main(args)
else
    show_help()
end
