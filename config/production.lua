-- config/production.lua
-- Configuração para ambiente de produção
-- IMPORTANTE: Use variáveis de ambiente (.env) para dados sensíveis

local env = require("crescent.utils.env")

local config = {
    -- Servidor
    server = {
        host = env.get("APP_HOST", "127.0.0.1"), -- Localhost quando atrás de Nginx/Apache
        port = tonumber(env.get("APP_PORT", "8080")),
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
        methods = env.get("CORS_METHODS", "GET,POST,PUT,PATCH,DELETE"),
        headers = "Content-Type, Authorization",
        credentials = true,
        max_age = 86400 -- 24 horas
    },
    
    -- Segurança
    security = {
        headers = true,
        rate_limit = env.get("RATE_LIMIT_ENABLED", "true") == "true",
        rate_limit_window = tonumber(env.get("RATE_LIMIT_WINDOW", "60")),
        rate_limit_max = tonumber(env.get("RATE_LIMIT_MAX", "100")),
        body_size_limit = true,
        path_traversal = true
    },
    
    -- Logging
    logging = {
        enabled = true,
        level = "basic" -- Menos verboso em produção
    },
    
    -- Database (SEMPRE use variáveis de ambiente em produção!)
    database = {
        host = env.get("DB_HOST"),
        port = tonumber(env.get("DB_PORT")),
        name = env.get("DB_NAME"),
        user = env.get("DB_USER"),
        password = env.get("DB_PASSWORD") -- NUNCA commite senhas no código!
    },
    
    -- JWT (OBRIGATÓRIO em produção)
    jwt = {
        secret = env.get("JWT_SECRET") -- ERRO se não definido
    },
    
    -- API
    api = {
        key = env.get("API_KEY")
    }
}

-- Fail-fast: antes, faltar JWT_SECRET/credenciais de banco em produção não
-- era detectado no boot — o comentário "ERRO se não definido" ao lado de
-- jwt.secret era só aspiracional, nada validava de fato. A app subia
-- normalmente e só quebrava depois, no primeiro request que usasse auth
-- (erro dentro de auth.lua) ou banco (erro cru dentro de mysql.lua).
-- Melhor falhar alto e claro aqui, no carregamento da config, do que numa
-- request de produção real.
local missing = {}
if not config.jwt.secret or config.jwt.secret == "" then
    table.insert(missing, "JWT_SECRET")
end
if not config.database.name or config.database.name == "" then
    table.insert(missing, "DB_NAME")
end
if not config.database.user or config.database.user == "" then
    table.insert(missing, "DB_USER")
end

if #missing > 0 then
    error("Configuração de produção incompleta — variáveis de ambiente faltando: " ..
          table.concat(missing, ", ") ..
          ". Defina no .env antes de subir em produção (ver INSTALLATION.md).")
end

return config

