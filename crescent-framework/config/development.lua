-- config/development.lua
-- Configuração para ambiente de desenvolvimento

local env = require("crescent.utils.env")

return {
    -- Servidor
    server = {
        host = env.get("APP_HOST", "0.0.0.0"),
        port = tonumber(env.get("APP_PORT", "8080")),
        max_body_size = 10 * 1024 * 1024 -- 10MB
    },
    
    -- CORS (permissivo em dev)
    cors = {
        enabled = true,
        origin = env.get("CORS_ORIGIN", "*"),
        methods = env.get("CORS_METHODS", "GET,POST,PUT,PATCH,DELETE,OPTIONS"),
        headers = "Content-Type, Authorization",
        credentials = false
    },
    
    -- Segurança
    security = {
        headers = true, -- Adiciona headers de segurança
        rate_limit = env.get("RATE_LIMIT_ENABLED", "false") == "true",
        rate_limit_max = tonumber(env.get("RATE_LIMIT_MAX", "100")),
        rate_limit_window = tonumber(env.get("RATE_LIMIT_WINDOW", "60")),
        body_size_limit = true,
        path_traversal = true
    },
    
    -- Logging
    logging = {
        enabled = true,
        level = "detailed" -- "basic", "detailed", "custom"
    },
    
    -- Database (usa .env para dados sensíveis)
    database = {
        host = env.get("DB_HOST", "localhost"),
        port = tonumber(env.get("DB_PORT", "5432")),
        name = env.get("DB_NAME", "dev_db"),
        user = env.get("DB_USER", "dev_user"),
        password = env.get("DB_PASSWORD", "dev_pass")
    },
    
    -- JWT
    jwt = {
        secret = env.get("JWT_SECRET", "change_this_in_production")
    },
    
    -- API
    api = {
        key = env.get("API_KEY")
    }
}
