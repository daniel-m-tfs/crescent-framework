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
    error_handler = nil,
}
