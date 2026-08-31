-- cli/commands/test.lua
-- Comando test (executa todos os testes do projeto)

local cli_output = require('crescent.utils.cli_output')
local colors = cli_output.colors
local print_header = cli_output.print_header
local print_error = cli_output.print_error
local print_info = cli_output.print_info

local M = {}

function M.run()
    print_header("Executando Testes Crescent")

    -- Procura por diretórios de teste
    local test_dirs = {}

    -- Verifica se existe pasta "tests"
    local tests_check = os.execute('test -d "tests" 2>/dev/null')
    if tests_check == 0 then
        table.insert(test_dirs, "tests")
    end

    -- Verifica se existe pasta "test"
    local test_check = os.execute('test -d "test" 2>/dev/null')
    if test_check == 0 then
        table.insert(test_dirs, "test")
    end

    if #test_dirs == 0 then
        print_error("Nenhum diretório de testes encontrado!")
        print_info("Crie um diretório 'tests' ou 'test' e adicione arquivos de teste.")
        return
    end

    -- Encontra todos os arquivos de teste
    local test_files = {}

    for _, dir in ipairs(test_dirs) do
        -- Usa find para buscar arquivos que contém "test" ou "tests" no nome
        local find_cmd = string.format([[find "%s" -type f \( -name "*test*.lua" -o -name "*tests*.lua" \) 2>/dev/null]], dir)
        local handle = io.popen(find_cmd)

        if handle then
            for file in handle:lines() do
                table.insert(test_files, file)
            end
            handle:close()
        end
    end

    if #test_files == 0 then
        print_error("Nenhum arquivo de teste encontrado!")
        print_info("Os arquivos de teste devem conter 'test' ou 'tests' no nome (ex: test-user.lua)")
        return
    end

    -- Executa cada arquivo de teste
    print_info(string.format("Encontrados %d arquivo(s) de teste\n", #test_files))

    local total_suites = 0
    local total_passed = 0
    local total_failed = 0

    for _, test_file in ipairs(test_files) do
        print(colors.bold .. "\n📄 Executando: " .. test_file .. colors.reset)
        print(string.rep("─", 60) .. "\n")

        local cmd = string.format('luvit "%s" 2>&1; echo "EXIT_CODE:$?"', test_file)
        local handle = io.popen(cmd)

        if handle then
            local output = handle:read("*a")
            handle:close()

            -- Extrai o exit code da saída
            local exit_code_str = output:match("EXIT_CODE:(%d+)")
            local exit_code = tonumber(exit_code_str) or 1

            -- Remove o exit code da saída
            output = output:gsub("EXIT_CODE:%d+\n?$", "")

            -- Exibe a saída do teste
            print(output)

            total_suites = total_suites + 1

            -- Verifica se o teste passou ou falhou
            if exit_code == 0 then
                total_passed = total_passed + 1
            else
                total_failed = total_failed + 1
            end
        else
            print_error("Falha ao executar teste: " .. test_file)
            total_suites = total_suites + 1
            total_failed = total_failed + 1
        end
    end

    -- Resumo final
    print(colors.bold .. "\n" .. string.rep("═", 60) .. colors.reset)
    print_header("Resumo dos Testes")

    print(string.format("Total de arquivos executados: %d", total_suites))

    if total_failed == 0 then
        print(colors.green .. colors.bold .. string.format("\n✅ Todos os testes passaram! (%d/%d)", total_passed, total_suites) .. colors.reset)
    else
        print(colors.red .. colors.bold .. string.format("\n❌ Alguns testes falharam! (%d passou, %d falhou)", total_passed, total_failed) .. colors.reset)
    end

    print("")
end

return M
