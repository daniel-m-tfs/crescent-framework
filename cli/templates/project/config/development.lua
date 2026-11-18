local Env = require("crescent.env")

return {
    environment = "development",
    debug = Env.boolean("APP_DEBUG", true),
    server = {
        host = "127.0.0.1",
        port = 8080,
        max_body_size = 10 * 1024 * 1024,
    },
    database = {
        host = Env.get("DB_HOST", "127.0.0.1"),
        port = Env.number("DB_PORT", 3306),
        database = Env.get("DB_NAME", "{{db_name}}_dev"),
        user = Env.get("DB_USER", "crescent"),
        password = Env.get("DB_PASSWORD", ""),
    },
    -- Used by the "redis" cache/queue drivers (lua-resty-redis, bundled).
    redis = {
        host = Env.get("REDIS_HOST", "127.0.0.1"),
        port = Env.number("REDIS_PORT", 6379),
        password = Env.get("REDIS_PASSWORD"),
        database = Env.number("REDIS_DB", 0),
    },
    -- ctx.cache: "shared" (this server's memory) or "redis".
    cache = {
        driver = Env.get("CACHE_DRIVER", "shared"),
        prefix = "{{db_name}}:cache:",
        ttl = 3600,
    },
    -- ctx.queue: "shared" (embedded workers), "redis" (lua cli.lua queue:work) or "sync".
    queue = {
        driver = Env.get("QUEUE_DRIVER", "shared"),
        prefix = "{{db_name}}:queue:",
    },
    error_handler = nil,
}
