-- cli/commands/new.lua
-- Comando new (cria um novo projeto Crescent clonando o starter do GitHub)

local cli_output = require('crescent.utils.cli_output')
local colors = cli_output.colors
local print_header = cli_output.print_header
local print_error = cli_output.print_error
local print_info = cli_output.print_info
local print_success = cli_output.print_success

local M = {}

function M.run(project_name)
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

return M
