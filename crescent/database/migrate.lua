-- crescent/database/migrate.lua - Sistema de migrations
require("../../bootstrap")

local MySQL = require("crescent.database.mysql")

local cli_output = require("crescent.utils.cli_output")
local colors = cli_output.colors
local print_header = cli_output.print_header
local print_success = cli_output.print_success
local print_error = cli_output.print_error
local print_info = cli_output.print_info
local print_debug = cli_output.print_debug

local Migrate = {}

-- Executa migrations pendentes
function Migrate.run()
    print_header("Executando Migrations")
    
    -- Cria tabela de migrations se não existir
    local create_table = [[
        CREATE TABLE IF NOT EXISTS migrations (
            id INT AUTO_INCREMENT PRIMARY KEY,
            migration VARCHAR(255) NOT NULL UNIQUE,
            batch INT NOT NULL,
            executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
    
    local result, err = MySQL:query(create_table)
    if err then
        print_error("Erro ao criar tabela migrations: " .. err)
        return
    end
    
    -- Busca qual é o próximo batch
    local batch_result = MySQL:query("SELECT MAX(batch) as max_batch FROM migrations")
    local current_batch = 1
    if batch_result and batch_result[1] and batch_result[1].max_batch then
        current_batch = tonumber(batch_result[1].max_batch) + 1
    end
    
    -- Busca migrations já executadas
    local executed_result = MySQL:query("SELECT migration FROM migrations")
    local executed = {}
    if executed_result then
        for _, row in ipairs(executed_result) do
            executed[row.migration] = true
        end
    end
    
    -- Lista arquivos de migration
    local handle = io.popen('ls migrations/*.lua 2>/dev/null | sort')
    if not handle then
        print_info("Nenhuma migration encontrada")
        return
    end
    
    local files = handle:read("*a")
    handle:close()
    
    if files == "" then
        print_info("Nenhuma migration encontrada")
        return
    end
    
    local pending = 0
    for file in files:gmatch("[^\r\n]+") do
        local migration_name = file:match("migrations/(.+)%.lua$")
        
        if migration_name and not executed[migration_name] then
            pending = pending + 1
            print(colors.yellow .. "→ Executando: " .. migration_name .. colors.reset)
            
            -- Carrega migration
            local migration_ok, migration = pcall(require, file:gsub("%.lua$", ""))
            
            if not migration_ok then
                print_error("  Erro ao carregar migration: " .. tostring(migration))
                goto continue
            end
            
            -- Executa up()
            local sql = migration:up()
            if not sql or sql == "" then
                print_error("  Migration não retornou SQL válido")
                goto continue
            end
            
            -- Mostra preview do SQL
            local sql_preview = sql:gsub("%s+", " "):sub(1, 80)
            print_debug("SQL: " .. sql_preview .. "...")
            
            -- Executa SQL
            local exec_result, exec_err = MySQL:query(sql)
            if exec_err then
                print_error("  Erro ao executar SQL: " .. exec_err)
                print_debug("SQL completo:")
                print_debug(sql)
                goto continue
            end
            
            print_debug("Resultado do SQL: " .. type(exec_result))
            if type(exec_result) == "table" and exec_result.affected then
                print_debug("Linhas afetadas: " .. exec_result.affected)
            end
            
            -- Registra migration como executada
            local insert_result, insert_err = MySQL:execute(
                "INSERT INTO migrations (migration, batch) VALUES (?, ?)",
                { migration_name, current_batch }
            )
            if insert_err then
                print_error("  Erro ao registrar migration: " .. insert_err)
                goto continue
            end
            
            print_success("  Executada com sucesso!")
        end
        
        ::continue::
    end
    
    if pending == 0 then
        print_info("Nenhuma migration pendente")
    else
        print("")
        print_success(string.format("Total: %d migration(s) executada(s)", pending))
    end
end

-- Desfaz último batch de migrations
function Migrate.rollback()
    print_header("Rollback de Migrations")
    
    -- Busca último batch
    local batch_result = MySQL:query([[
        SELECT MAX(batch) as max_batch FROM migrations
    ]])
    
    if not batch_result or not batch_result[1] or not batch_result[1].max_batch then
        print_info("Nenhuma migration para desfazer")
        return
    end
    
    local last_batch = tonumber(batch_result[1].max_batch)
    
    -- Busca migrations do último batch
    local migrations_result = MySQL:execute([[
        SELECT migration FROM migrations
        WHERE batch = ?
        ORDER BY id DESC
    ]], { last_batch })
    
    if not migrations_result or #migrations_result == 0 then
        print_info("Nenhuma migration para desfazer")
        return
    end
    
    local rolled_back = 0
    for _, row in ipairs(migrations_result) do
        local migration_name = row.migration
        print(colors.yellow .. "→ Desfazendo: " .. migration_name .. colors.reset)
        
        local file = "migrations/" .. migration_name .. ".lua"
        local migration_ok, migration = pcall(require, file:gsub("%.lua$", ""))
        
        if not migration_ok then
            print_error("  Erro ao carregar migration: " .. tostring(migration))
            goto continue
        end
        
        -- Executa down()
        local sql = migration:down()
        if not sql or sql == "" then
            print_error("  Migration não retornou SQL válido para rollback")
            goto continue
        end
        
        local exec_result, exec_err = MySQL:query(sql)
        if exec_err then
            print_error("  Erro ao executar rollback: " .. exec_err)
            goto continue
        end
        
        -- Remove registro da migration
        MySQL:execute("DELETE FROM migrations WHERE migration = ?", { migration_name })
        
        rolled_back = rolled_back + 1
        print_success("  Rollback executado!")
        
        ::continue::
    end
    
    print("")
    print_success(string.format("Total: %d migration(s) desfeita(s)", rolled_back))
end

-- Mostra status das migrations
function Migrate.status()
    print_header("Status das Migrations")
    
    -- Busca migrations executadas
    local executed_result = MySQL:query([[
        SELECT migration, batch, executed_at 
        FROM migrations 
        ORDER BY id
    ]])
    
    local executed = {}
    if executed_result then
        for _, row in ipairs(executed_result) do
            executed[row.migration] = {
                batch = row.batch,
                executed_at = row.executed_at
            }
        end
    end
    
    -- Lista todos os arquivos
    local handle = io.popen('ls migrations/*.lua 2>/dev/null | sort')
    if not handle then
        print_info("Nenhuma migration encontrada")
        return
    end
    
    local files = handle:read("*a")
    handle:close()
    
    if files == "" then
        print_info("Nenhuma migration encontrada")
        return
    end
    
    print(string.format("%-50s %-10s %s", "Migration", "Status", "Batch"))
    print(string.rep("-", 80))
    
    for file in files:gmatch("[^\r\n]+") do
        local migration_name = file:match("migrations/(.+)%.lua$")
        
        if migration_name then
            local info = executed[migration_name]
            if info then
                print(string.format(
                    "%-50s %s%-10s%s %s",
                    migration_name:sub(1, 50),
                    colors.green,
                    "Executada",
                    colors.reset,
                    info.batch
                ))
            else
                print(string.format(
                    "%-50s %s%-10s%s",
                    migration_name:sub(1, 50),
                    colors.yellow,
                    "Pendente",
                    colors.reset
                ))
            end
        end
    end
    
    print("")
end

-- Executa comando baseado nos argumentos
local command = process.argv[2] or "help"

if command == "migrate" then
    Migrate.run()
elseif command == "rollback" then
    Migrate.rollback()
elseif command == "status" then
    Migrate.status()
else
    print("Uso:")
    print("  luvit crescent/database/migrate.lua migrate   - Executa migrations pendentes")
    print("  luvit crescent/database/migrate.lua rollback  - Desfaz último batch")
    print("  luvit crescent/database/migrate.lua status    - Mostra status")
end

return Migrate
