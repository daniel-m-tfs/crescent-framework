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
    end

    return ctx.json(404, { error = "Not found" })
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
    local model_name = capitalize(name)
    local model_file = to_snake_case(name)
    return string.format([[-- src/%s/services/%s.lua
-- Service para lógica de negócio de %s

local %s = {}
local %s = require("src.%s.models.%s")

function %s:getAll()
    return %s:all()
end

function %s:getById(id)
    return %s:find(id)
end

function %s:create(body)
   return %s:create(body)
end

function %s:update(id, body)
    local %s = %s:find(id)
    if %s then
        %s:update(body)
        return %s
    end
    return nil
end

function %s:delete(id)
    local %s = %s:find(id)
    if %s then
        %s:delete()
        return true
    end
    return false
end

return %s
]], module_name, to_snake_case(name), name,
    class_name, model_name, module_name, model_file,
    class_name, model_name,
    class_name, model_name,
    class_name, model_name,
    class_name, to_snake_case(name), model_name, to_snake_case(name),
    to_snake_case(name), to_snake_case(name),
    class_name, to_snake_case(name), model_name, to_snake_case(name),
    to_snake_case(name),
    class_name)
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
        "name",
    },
    
    hidden = {
        -- Campos que não devem aparecer em JSON/serialização
        -- "password"
    },

    guarded = {
        -- Campos protegidos contra mass assignment
        -- "id", "created_at", "updated_at"
    },
    
    validates = {
        -- Adicione validações aqui
        name = {required = true, min = 3, max = 255},
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
    local snake_name = to_snake_case(name)
    return string.format([[-- src/%s/routes/%s.lua
-- Rotas para %s
-- prefix definido em %s/init.lua

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
]], module_name, snake_name, name, snake_name,
    module_name, snake_name, snake_name)
end

templates.module = function(name)
    local module_name = to_snake_case(name)
    local snake_name = to_snake_case(name)
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
    module_name, snake_name, snake_name, capitalize(name))
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

-- Command: server (inicia o servidor)
commands.server = function()
    print_header("Iniciando Servidor Crescent")
    
    -- Verifica se app.lua existe
    local app_file = io.open("app.lua", "r")
    if not app_file then
        print_error("Arquivo app.lua não encontrado!")
        print_info("Execute este comando no diretório raiz do projeto Crescent.")
        return
    end
    app_file:close()
    
    -- Inicia o servidor substituindo o processo atual
    -- Isso mantém a saída interativa e os logs em tempo real
    print_info("Iniciando aplicação...\n")
    os.execute("exec luvit app.lua")
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
    
    -- Verifica se git está instalado
    local git_check = os.execute('command -v git >/dev/null 2>&1')
    if git_check ~= 0 then
        print_error("Git não está instalado! Por favor, instale o Git e tente novamente.")
        return
    end
    
    -- Clona o template do GitHub
    print_info("Clonando template do GitHub...")
    local clone_cmd = string.format('git clone https://github.com/daniel-m-tfs/crescent-starter.git "%s"', project_name)
    local clone_result = os.execute(clone_cmd)
    
    if clone_result ~= 0 then
        print_error("Falha ao clonar o repositório do GitHub!")
        return
    end
    
    print_success("Projeto clonado com sucesso!")
    
    -- Remove o histórico git do template
    print_info("Removendo histórico git do template...")
    local remove_git_cmd = string.format('rm -rf "%s/.git"', project_name)
    os.execute(remove_git_cmd)
    
    -- Inicializa novo repositório git
    print_info("Inicializando novo repositório git...")
    local init_git_cmd = string.format('cd "%s" && git init', project_name)
    os.execute(init_git_cmd)
    
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

  new <nome>                        Cria um novo projeto Crescent (clona do GitHub)
  server                            Inicia o servidor de desenvolvimento
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
  luvit crescent-cli server
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
    elseif command == "server" then
        commands.server()
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
