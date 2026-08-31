-- cli/commands/make.lua
-- Comandos make:controller, make:service, make:model, make:routes, make:module, make:migration

local cli_output = require('crescent.utils.cli_output')
local colors = cli_output.colors
local print_success = cli_output.print_success
local print_info = cli_output.print_info
local print_error = cli_output.print_error
local print_header = cli_output.print_header

local templates = require('cli.templates')

local M = {}

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

function M.controller(name, module_name)
    module_name = module_name or templates.to_snake_case(name)
    local dir = string.format("src/%s/controllers", module_name)
    ensure_dir(dir)

    local filepath = string.format("%s/%s.lua", dir, templates.to_snake_case(name))
    local content = templates.controller(name, module_name)

    if write_file(filepath, content) then
        print_success("Controller criado: " .. filepath)
    else
        print_error("Erro ao criar controller")
    end
end

function M.service(name, module_name)
    module_name = module_name or templates.to_snake_case(name)
    local dir = string.format("src/%s/services", module_name)
    ensure_dir(dir)

    local filepath = string.format("%s/%s.lua", dir, templates.to_snake_case(name))
    local content = templates.service(name, module_name)

    if write_file(filepath, content) then
        print_success("Service criado: " .. filepath)
    else
        print_error("Erro ao criar service")
    end
end

function M.model(name, module_name)
    module_name = module_name or templates.to_snake_case(name)
    local dir = string.format("src/%s/models", module_name)
    ensure_dir(dir)

    local filepath = string.format("%s/%s.lua", dir, templates.to_snake_case(name))
    local content = templates.model(name, module_name)

    if write_file(filepath, content) then
        print_success("Model criado: " .. filepath)
    else
        print_error("Erro ao criar model")
    end
end

function M.routes(name, module_name)
    module_name = module_name or templates.to_snake_case(name)
    local dir = string.format("src/%s/routes", module_name)
    ensure_dir(dir)

    local filepath = string.format("%s/%s.lua", dir, templates.to_snake_case(name))
    local content = templates.routes(name, module_name)

    if write_file(filepath, content) then
        print_success("Routes criadas: " .. filepath)
    else
        print_error("Erro ao criar routes")
    end
end

function M.module(name)
    local module_name = templates.to_snake_case(name)
    local dir = string.format("src/%s", module_name)
    ensure_dir(dir)

    -- Cria todas as estruturas
    print_header("Criando módulo " .. templates.capitalize(name))

    M.controller(name, module_name)
    M.service(name, module_name)
    M.model(name, module_name)
    M.routes(name, module_name)

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
function M.migration(name)
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

return M
