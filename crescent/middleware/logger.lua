-- crescent/middleware/logger.lua
-- Middleware de logging de requisições

local M = {}

-- Formata timestamp
local function format_time()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Logger básico (stdout)
function M.basic()
    return function(ctx, next)
        local start_time = os.clock()
        
        -- Log da requisição
        print(string.format("[%s] %s %s", 
              format_time(), 
              ctx.method, 
              ctx.path))
        
        -- Executa próximo middleware/handler
        local result = next and next() or true
        
        -- Log da resposta
        local duration = (os.clock() - start_time) * 1000
        local status = ctx.res.statusCode or 200
        
        print(string.format("[%s] %s %s - %d (%.2fms)", 
              format_time(), 
              ctx.method, 
              ctx.path, 
              status, 
              duration))
        
        return result
    end
end

-- Logger detalhado
function M.detailed()
    return function(ctx, next)
        local start_time = os.clock()
        
        -- Log detalhado da requisição
        print(string.format("\n=== [%s] Request ===", format_time()))
        print(string.format("Method: %s", ctx.method))
        print(string.format("Path: %s", ctx.path))
        print(string.format("Route: %s", ctx.route or "N/A"))
        
        -- Query params
        if next(ctx.query) then
            print("Query:")
            for k, v in pairs(ctx.query) do
                print(string.format("  %s = %s", k, v))
            end
        end
        
        -- Route params
        if next(ctx.params) then
            print("Params:")
            for k, v in pairs(ctx.params) do
                print(string.format("  %s = %s", k, v))
            end
        end
        
        -- Headers importantes
        print("Headers:")
        local important_headers = {"authorization", "content-type", "user-agent"}
        for _, h in ipairs(important_headers) do
            local v = ctx.getHeader(h)
            if v then
                print(string.format("  %s: %s", h, v))
            end
        end
        
        -- Executa
        local result = next and next() or true
        
        -- Log da resposta
        local duration = (os.clock() - start_time) * 1000
        local status = ctx.res.statusCode or 200
        
        print(string.format("\n=== Response ==="))
        print(string.format("Status: %d", status))
        print(string.format("Duration: %.2fms", duration))
        print()
        
        return result
    end
end

-- Logger customizado
function M.custom(formatter)
    if type(formatter) ~= "function" then
        error("formatter must be a function")
    end
    
    return function(ctx, next)
        local start_time = os.clock()
        
        local result = next and next() or true
        
        local duration = (os.clock() - start_time) * 1000
        local status = ctx.res.statusCode or 200
        
        local log_data = {
            timestamp = format_time(),
            method = ctx.method,
            path = ctx.path,
            route = ctx.route,
            status = status,
            duration = duration,
            query = ctx.query,
            params = ctx.params
        }
        
        local message = formatter(log_data, ctx)
        if message then
            print(message)
        end
        
        return result
    end
end

return M
