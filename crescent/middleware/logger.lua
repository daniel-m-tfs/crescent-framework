-- crescent/middleware/logger.lua
-- Middleware de logging de requisições

local M = {}

-- Formata timestamp
local function format_time()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Executa a próxima etapa da cadeia e retorna seu resultado, tratando
-- corretamente o caso "next_fn() retornou false" (o mecanismo oficial de
-- halt do framework — ver server.lua). O idiom antigo, `next and next() or
-- true`, colapsava um `false` legítimo de next() em `true` (Lua avalia
-- `false or true` como `true`), fazendo qualquer middleware de bloqueio
-- registrado DEPOIS do logger ser silenciosamente ignorado.
local function call_next(next_fn)
    if next_fn == nil then
        return true
    end
    return next_fn() ~= false
end

-- Logger básico (stdout)
function M.basic()
    return function(ctx, next_fn)
        local start_time = os.clock()

        -- Log da requisição
        print(string.format("[%s] %s %s",
              format_time(),
              ctx.method,
              ctx.path))

        -- Executa próximo middleware/handler
        local result = call_next(next_fn)

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
    return function(ctx, next_fn)
        local start_time = os.clock()

        -- Log detalhado da requisição
        print(string.format("\n=== [%s] Request ===", format_time()))
        print(string.format("Method: %s", ctx.method))
        print(string.format("Path: %s", ctx.path))
        print(string.format("Route: %s", ctx.route or "N/A"))

        -- Query params. Usa o `next` GLOBAL do Lua (iterador de tabela) —
        -- antes, o parâmetro da função também se chamava `next` e sombreava
        -- o global, fazendo esta chamada disparar a cadeia de middlewares
        -- adiante prematuramente (e de novo depois, na linha de baixo:
        -- execução dupla do handler sempre que ctx.query não era vazio).
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
        local result = call_next(next_fn)

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

    return function(ctx, next_fn)
        local start_time = os.clock()

        local result = call_next(next_fn)

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
