#!/usr/bin/env luvit
-- crescent-cli
-- CLI para geração de código no estilo Artisan/NestJS

local cli_output = require('crescent.utils.cli_output')
local print_header = cli_output.print_header

local make = require('cli.commands.make')
local migrate = require('cli.commands.migrate')
local server = require('cli.commands.server')
local new_cmd = require('cli.commands.new')
local test_cmd = require('cli.commands.test')

-- Help
local function show_help()
    print_header("Crescent CLI - Gerador de Código")
    print([[
Uso: luvit crescent-cli <comando> [opções]

Comandos disponíveis:

  new <nome>                        Cria um novo projeto Crescent (clona do GitHub)
  server                            Inicia o servidor de desenvolvimento
  test                              Executa todos os testes do projeto
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
  luvit crescent-cli test
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
        new_cmd.run(name)
    elseif command == "server" then
        server.run()
    elseif command == "test" then
        test_cmd.run()
    elseif command == "make:controller" and name then
        make.controller(name, module_name)
    elseif command == "make:service" and name then
        make.service(name, module_name)
    elseif command == "make:model" and name then
        make.model(name, module_name)
    elseif command == "make:routes" and name then
        make.routes(name, module_name)
    elseif command == "make:module" and name then
        make.module(name)
    elseif command == "make:migration" and name then
        make.migration(name)
    elseif command == "migrate" then
        migrate.run()
    elseif command == "migrate:rollback" then
        migrate.rollback()
    elseif command == "migrate:status" then
        migrate.status()
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
