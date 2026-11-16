local config = {
    environment = "development",
    debug = true,
    server = {
        host = "127.0.0.1",
        port = 8080,
        max_body_size = 10 * 1024 * 1024,
    },
    error_handler = nil,
}

return config
