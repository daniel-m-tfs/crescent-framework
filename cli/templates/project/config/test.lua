local Env = require("crescent.env")

return {
    environment = "test",
    debug = true,
    server = {
        host = "127.0.0.1",
        port = 8080,
        max_body_size = 10 * 1024 * 1024,
    },
    database = {
        host = Env.get("DB_HOST", "127.0.0.1"),
        port = Env.number("DB_PORT", 3306),
        database = Env.get("DB_TEST_NAME", "{{db_name}}_test"),
        user = Env.get("DB_USER", "root"),
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
        driver = "shared",
        prefix = "{{db_name}}_test:cache:",
        ttl = 3600,
    },
    -- ctx.queue: "shared" (embedded workers), "redis" (lua cli.lua queue:work) or "sync".
    queue = {
        driver = "sync",
        prefix = "{{db_name}}_test:queue:",
    },
    error_handler = nil,
}
