-- config/development.lua
-- Configuração para ambiente de desenvolvimento

return {
    -- Servidor
    server = {
        host = "0.0.0.0",
        port = 8080,
        max_body_size = 10 * 1024 * 1024 -- 10MB
    },
    
    -- CORS (permissivo em dev)
    cors = {
        enabled = true,
        origin = "*",
        methods = "GET,POST,PUT,PATCH,DELETE,OPTIONS",
        headers = "Content-Type, Authorization",
        credentials = false
    },
    
    -- Segurança
    security = {
        headers = true, -- Adiciona headers de segurança
        rate_limit = false, -- Desabilitado em dev
        body_size_limit = true,
        path_traversal = true
    },
    
    -- Logging
    logging = {
        enabled = true,
        level = "detailed" -- "basic", "detailed", "custom"
    },
    
    -- Database (exemplo)
    database = {
        host = "localhost",
        port = 5432,
        name = "dev_db",
        user = "dev_user",
        password = "dev_pass"
    }
}
