-- cli/commands/migrate.lua
-- Comandos migrate, migrate:rollback, migrate:status (delegam para crescent/database/migrate.lua)

local M = {}

function M.run()
    local handle = io.popen("luvit crescent/database/migrate.lua migrate 2>&1")
    if handle then
        local output = handle:read("*a")
        handle:close()
        print(output)
    end
end

function M.rollback()
    local handle = io.popen("luvit crescent/database/migrate.lua rollback 2>&1")
    if handle then
        local output = handle:read("*a")
        handle:close()
        print(output)
    end
end

function M.status()
    local handle = io.popen("luvit crescent/database/migrate.lua status 2>&1")
    if handle then
        local output = handle:read("*a")
        handle:close()
        print(output)
    end
end

return M
