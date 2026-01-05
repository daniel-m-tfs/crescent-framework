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
    return string.format([[-- src/%s/models/%s.lua
-- Model/Entity para %s

local %s = {}
%s.__index = %s

function %s.new(data)
    local self = setmetatable({}, %s)
    self.id = data.id
    self.created_at = data.created_at or os.time()
    self.updated_at = data.updated_at
    return self
end

function %s:validate()
    -- Adicione validações aqui
    if not self.id then
        return false, "ID é obrigatório"
    end
    return true
end

function %s:toTable()
    return {
        id = self.id,
        created_at = self.created_at,
        updated_at = self.updated_at
    }
end

return %s
]], module_name, to_snake_case(name), name,
    class_name, class_name, class_name,
    class_name, class_name, class_name, class_name, class_name)
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

-- Help
local function show_help()
    print_header("Crescent CLI - Gerador de Código")
    print([[
Uso: luvit crescent-cli <comando> [opções]

Comandos disponíveis:

  make:controller <nome> [módulo]   Cria um controller
  make:service <nome> [módulo]      Cria um service
  make:model <nome> [módulo]        Cria um model
  make:routes <nome> [módulo]       Cria arquivo de rotas
  make:module <nome>                Cria um módulo completo (CRUD)

Exemplos:

  luvit crescent-cli make:module User
  luvit crescent-cli make:controller Product
  luvit crescent-cli make:service Auth auth
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
    
    if command == "make:controller" and name then
        commands.make.controller(name, module_name)
    elseif command == "make:service" and name then
        commands.make.service(name, module_name)
    elseif command == "make:model" and name then
        commands.make.model(name, module_name)
    elseif command == "make:routes" and name then
        commands.make.routes(name, module_name)
    elseif command == "make:module" and name then
        commands.make.module(name)
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
