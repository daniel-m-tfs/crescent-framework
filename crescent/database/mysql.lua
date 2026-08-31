-- crescent/database/mysql.lua
-- MySQL Connection Manager com prepared statements

local env = require("crescent.utils.env")
local sql_escape = require("crescent.database.sql_escape")

local MySQL = {}
MySQL.__index = MySQL

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

-- Cria nova conexão
function MySQL.connect()
    if not driver_available then
        return nil, "Driver MySQL não instalado. Execute: luarocks install luasql-mysql"
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

        local alive = pcall(function() return conn:execute("SELECT 1") end)
        if alive then
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
    local escaped_sql = sql
    if params and #params > 0 then
        for i, param in ipairs(params) do
            escaped_sql = escaped_sql:gsub("?", sql_escape.escape_value(param), 1)
        end
    end

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
    local escaped_sql = sql
    if params and #params > 0 then
        for i, param in ipairs(params) do
            escaped_sql = escaped_sql:gsub("?", sql_escape.escape_value(param), 1)
        end
    end

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
