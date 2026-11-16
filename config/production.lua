local Env = require("crescent.env")

return {
    environment = "production",
    debug = false,
    server = {
        host = "127.0.0.1",
        port = 8080,
        max_body_size = 5 * 1024 * 1024,
    },
    database = {
        host = Env.get("DB_HOST"),
        port = Env.number("DB_PORT", 3306),
        database = Env.get("DB_NAME"),
        user = Env.get("DB_USER"),
        password = Env.get("DB_PASSWORD"),
    },
    error_handler = nil,
}
