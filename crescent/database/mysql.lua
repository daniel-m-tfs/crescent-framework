-- crescent/database/mysql.lua
-- MySQL Connection Manager com prepared statements

local env = require("crescent.utils.env")
local sql_escape = require("crescent.database.sql_escape")

local MySQL = {}
MySQL.__index = MySQL

-- Substitui os placeholders "?" de `sql` pelos valores de `params`, já
-- escapados. Faz isso numa ÚNICA passada de gsub usando uma FUNÇÃO como
-- replacement (não uma string) — isso é essencial por dois motivos:
-- 1. Se o replacement fosse uma string, "%" dentro dela é metacaractere de
--    captura do gsub ("%1".."%9"/"%%") e corrompe valores contendo "%"
--    (ex: "50% off").
-- 2. Substituir "?" um de cada vez, sequencialmente, confunde um "?" que
--    sobrou DENTRO de um valor já substituído com o placeholder seguinte.
-- Uma única passada com função-replacement resolve os dois problemas.
local function bind_params(sql, params)
    if not params or #params == 0 then
        return sql
    end
    local i = 0
    return (sql:gsub("%?", function()
        i = i + 1
        return sql_escape.escape_value(params[i])
    end))
end

-- Pool de conexões (simples)
local connection_pool = {}
local pool_size = 0
local MAX_POOL_SIZE = 10

-- Configuração
local config = {
    host = env.get("DB_HOST", "localhost"),
    port = tonumber(env.get("DB_PORT", "3306")),
    database = env.get("DB_NAME"),
    user = env.get("DB_USER"),
    password = env.get("DB_PASSWORD")
}

-- Tenta carregar driver MySQL
local driver = nil
local driver_available = false

-- Tenta luasql primeiro
local ok_luasql, luasql = pcall(require, "luasql.mysql")
if ok_luasql then
    driver = "luasql"
    driver_available = true
    print("✓ Driver MySQL: luasql")
else
    -- Fallback para mock se não tiver driver
    print("⚠️  Driver MySQL não encontrado (luasql-mysql)")
    print("   Execute: luarocks install luasql-mysql")
end

-- Valida que a configuração mínima necessária pra conectar está presente,
-- pra falhar com uma mensagem clara em vez de deixar o driver C estourar
-- "bad argument #1 to 'connect' (string expected, got nil)".
local function validate_config()
    local missing = {}
    if not config.database or config.database == "" then table.insert(missing, "DB_NAME") end
    if not config.user or config.user == "" then table.insert(missing, "DB_USER") end
    if not config.host or config.host == "" then table.insert(missing, "DB_HOST") end
    if #missing > 0 then
        return false, "Configuração de banco incompleta, faltando: " .. table.concat(missing, ", ")
    end
    return true
end

-- Cria nova conexão
function MySQL.connect()
    if not driver_available then
        return nil, "Driver MySQL não instalado. Execute: luarocks install luasql-mysql"
    end

    local config_ok, config_err = validate_config()
    if not config_ok then
        return nil, config_err
    end

    if driver == "luasql" then
        local env_obj = luasql.mysql()
        local conn, err = env_obj:connect(
            config.database,
            config.user,
            config.password,
            config.host,
            config.port
        )
        
        if not conn then
            return nil, "Falha ao conectar: " .. (err or "erro desconhecido")
        end
        
        -- Configura charset UTF-8
        conn:execute("SET NAMES utf8mb4")
        
        return conn, env_obj
    end
    
    return nil, "Driver desconhecido"
end

-- Pega conexão do pool ou cria nova
function MySQL.getConnection()
    if not driver_available then
        return nil, "Driver MySQL não disponível"
    end
    
    -- Se tem conexão disponível no pool, reutiliza (se ainda estiver viva)
    while pool_size > 0 do
        local conn = table.remove(connection_pool)
        pool_size = pool_size - 1

        -- luasql normalmente RETORNA nil,err numa conexão morta em vez de
        -- lançar erro Lua — pcall sozinho não detecta isso, precisa checar
        -- o retorno também.
        local ok, cursor = pcall(function() return conn:execute("SELECT 1") end)
        if ok and cursor then
            if type(cursor) ~= "boolean" then pcall(function() cursor:close() end) end
            return conn
        end

        pcall(function() conn:close() end)
    end

    -- Senão, cria nova
    return MySQL.connect()
end

-- Retorna conexão ao pool
function MySQL.releaseConnection(conn)
    if not conn then return end
    
    -- Limita tamanho do pool
    if pool_size < MAX_POOL_SIZE then
        table.insert(connection_pool, conn)
        pool_size = pool_size + 1
    else
        -- Pool cheio, fecha conexão
        conn:close()
    end
end

-- Executa query simples
function MySQL:query(sql)
    if not driver_available then
        print("⚠️  [MOCK] SQL:", sql)
        return { affected = 0, note = "Driver MySQL não instalado" }
    end
    
    local conn, env_obj = self.getConnection()
    if not conn then
        return nil, env_obj -- env_obj contém a mensagem de erro
    end
    
    local cursor, err = conn:execute(sql)
    
    if not cursor then
        conn:close()
        return nil, "Erro na query: " .. (err or "desconhecido")
    end
    
    -- Se é SELECT, busca resultados
    if type(cursor) == "userdata" then
        local results = {}
        local row = cursor:fetch({}, "a")
        
        while row do
            table.insert(results, row)
            row = cursor:fetch({}, "a")
        end
        
        cursor:close()
        self.releaseConnection(conn)
        
        return results
    end
    
    -- Se é INSERT/UPDATE/DELETE, retorna affected rows
    local affected = cursor
    self.releaseConnection(conn)
    
    return { affected = affected }
end

-- Executa query com prepared statement (seguro contra SQL injection)
function MySQL:execute(sql, params)
    if not driver_available then
        print("⚠️  [MOCK] SQL:", sql)
        if params and next(params) then
            print("⚠️  [MOCK] Params:", table.concat(params, ", "))
        end
        return { affected = 0, note = "Driver MySQL não instalado" }
    end
    
    local conn, env_obj = self.getConnection()
    if not conn then
        return nil, env_obj
    end
    
    -- Escapa parâmetros (fonte única: crescent.database.sql_escape)
    local escaped_sql = bind_params(sql, params)

    return self:query(escaped_sql)
end

-- Busca múltiplos registros
function MySQL:select(sql, params)
    return self:execute(sql, params)
end

-- Busca um único registro
function MySQL:selectOne(sql, params)
    local results = self:execute(sql, params)
    if results and #results > 0 then
        return results[1]
    end
    return nil
end

-- INSERT e retorna ID
function MySQL:insert(sql, params)
    if not driver_available then
        print("⚠️  [MOCK] SQL:", sql)
        return nil, "Driver MySQL não disponível"
    end
    
    local conn, env_obj = self.getConnection()
    if not conn then
        print("❌ Falha ao obter conexão:", env_obj)
        return nil, env_obj
    end
    
    -- Escapa parâmetros (fonte única: crescent.database.sql_escape)
    local escaped_sql = bind_params(sql, params)

    -- Executa INSERT
    local cursor, err = conn:execute(escaped_sql)
    
    if not cursor then
        print("❌ Erro no INSERT:", err or "desconhecido")
        self.releaseConnection(conn)
        return nil, "Erro na query: " .. (err or "desconhecido")
    end
    
    -- Pega último ID inserido (na MESMA conexão)
    local last_id_cursor, last_id_err = conn:execute("SELECT LAST_INSERT_ID() as id")
    if last_id_cursor then
        local row = last_id_cursor:fetch({}, "a")
        last_id_cursor:close()
        self.releaseConnection(conn)
        
        local inserted_id = row and tonumber(row.id) or nil
        return inserted_id
    else
        print("❌ Erro ao pegar LAST_INSERT_ID:", last_id_err or "desconhecido")
        self.releaseConnection(conn)
        return nil, "Failed to get inserted ID"
    end
end

-- UPDATE
function MySQL:update(sql, params)
    return self:execute(sql, params)
end

-- DELETE
function MySQL:delete(sql, params)
    return self:execute(sql, params)
end

-- Executa várias statements ({sql=, params=}) NA MESMA conexão, dentro de
-- uma transação: ou todas persistem, ou nenhuma (ROLLBACK no primeiro
-- erro). MySQL:query()/execute()/insert() normais pegam uma conexão do
-- pool POR CHAMADA e a devolvem em seguida — não dá pra usá-los pra
-- compor operações atômicas entre si; esta função existe exatamente pra
-- isso (ex: migrate.lua precisa que "rodar o SQL da migration" e
-- "registrar a migration como executada" aconteçam como uma coisa só).
function MySQL.transaction(statements)
    if not driver_available then
        return nil, "Driver MySQL não instalado. Execute: luarocks install luasql-mysql"
    end

    local config_ok, config_err = validate_config()
    if not config_ok then
        return nil, config_err
    end

    local conn, env_obj = MySQL.connect()
    if not conn then
        return nil, env_obj
    end

    local began = conn:execute("START TRANSACTION")
    if not began then
        pcall(function() conn:close() end)
        return nil, "Falha ao iniciar transação"
    end

    local results = {}
    for i, stmt in ipairs(statements) do
        local sql = bind_params(stmt.sql, stmt.params)
        local cursor, err = conn:execute(sql)

        if not cursor then
            pcall(function() conn:execute("ROLLBACK") end)
            pcall(function() conn:close() end)
            return nil, string.format("Erro na statement %d: %s", i, err or "desconhecido")
        end

        if type(cursor) == "userdata" then
            cursor:close()
            table.insert(results, true)
        else
            table.insert(results, cursor) -- affected rows (INSERT/UPDATE/DELETE)
        end
    end

    local committed = conn:execute("COMMIT")
    if not committed then
        pcall(function() conn:execute("ROLLBACK") end)
        pcall(function() conn:close() end)
        return nil, "Falha ao commitar transação"
    end

    MySQL.releaseConnection(conn)
    return results
end

-- Testa conexão
function MySQL.test()
    print("🔍 Testando conexão MySQL...")
    print("   Host:", config.host)
    print("   Port:", config.port)
    print("   Database:", config.database)
    print("   User:", config.user)
    print("")
    
    if not driver_available then
        print("❌ Driver não instalado")
        print("   Execute: luarocks install luasql-mysql")
        return false
    end
    
    local conn, err = MySQL.connect()
    if not conn then
        print("❌ Falha na conexão:", err)
        return false
    end
    
    print("✅ Conexão estabelecida com sucesso!")
    
    -- Testa query simples
    local cursor, err = conn:execute("SELECT VERSION() as version")
    if cursor then
        local row = cursor:fetch({}, "a")
        if row then
            print("   MySQL Version:", row.version)
        end
        cursor:close()
    end
    
    conn:close()
    return true
end

-- Fecha todas conexões do pool
function MySQL.closeAll()
    for _, conn in ipairs(connection_pool) do
        conn:close()
    end
    connection_pool = {}
    pool_size = 0
end

-- Verifica se o driver está disponível
function MySQL.isDriverAvailable()
    return driver_available
end

return MySQL
