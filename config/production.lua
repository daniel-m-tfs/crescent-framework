-- config/production.lua
-- Configuração para ambiente de produção

return {
    -- Servidor
    server = {
        host = "127.0.0.1", -- Localhost quando atrás de Nginx/Apache
        port = 8080,
        max_body_size = 5 * 1024 * 1024 -- 5MB (mais restritivo)
    },
    
    -- CORS (restritivo em prod)
    cors = {
        enabled = true,
        strict = true, -- Usa validação estrita de origins
        allowed_origins = {
            "https://yourdomain.com",
            "https://www.yourdomain.com",
            "https://api.yourdomain.com"
        },
        methods = "GET,POST,PUT,PATCH,DELETE",
        headers = "Content-Type, Authorization",
        credentials = true,
        max_age = 86400 -- 24 horas
    },
    
    -- Segurança
    security = {
        headers = true,
        rate_limit = true,
        rate_limit_window = 60, -- 60 segundos
        rate_limit_max = 100, -- 100 requisições por janela
        body_size_limit = true,
        path_traversal = true
    },
    
    -- Logging
    logging = {
        enabled = true,
        level = "basic" -- Menos verboso em produção
    },
    
    -- Database (exemplo - usar variáveis de ambiente)
    database = {
        host = os.getenv("DB_HOST") or "localhost",
        port = tonumber(os.getenv("DB_PORT")) or 5432,
        name = os.getenv("DB_NAME") or "prod_db",
        user = os.getenv("DB_USER") or "prod_user",
        password = os.getenv("DB_PASSWORD") or ""
    }
}
