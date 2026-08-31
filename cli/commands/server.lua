-- cli/commands/server.lua
-- Comando server (inicia o servidor)

local cli_output = require('crescent.utils.cli_output')
local print_header = cli_output.print_header
local print_error = cli_output.print_error
local print_info = cli_output.print_info

local M = {}

function M.run()
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

return M
