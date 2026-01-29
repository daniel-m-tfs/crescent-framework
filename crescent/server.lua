-- crescent/server.lua
-- Servidor HTTP principal do framework Crescent

-- Usa os módulos pré-carregados ou carrega normalmente
local http = _G._http or require("http")
local url = _G._url or require("url")
local router_lib = require("crescent.core.router")
local context_lib = require("crescent.core.context")
local request_lib = require("crescent.core.request")
local response_lib = require("crescent.core.response")

local Server = {}
Server.__index = Server

-- Cria nova instância do servidor
function Server.new()
    return setmetatable({
        router = router_lib.new(),
        middlewares = {},
        error_handler = nil,
        not_found_handler = nil,
        config = {
            max_body_size = 10 * 1024 * 1024 -- 10MB
        }
    }, Server)
end

-- Adiciona middleware global
function Server:use(middleware)
    if type(middleware) ~= "function" then
        error("Middleware must be a function")
    end
    table.insert(self.middlewares, middleware)
    return self
end

-- Define handler de erro customizado
function Server:on_error(handler)
    self.error_handler = handler
    return self
end

-- Define handler 404 customizado
function Server:on_not_found(handler)
    self.not_found_handler = handler
    return self
end

-- Métodos de roteamento
function Server:get(path, handler)
    router_lib.add_route(self.router, "GET", path, handler)
    return self
end

function Server:post(path, handler)
    router_lib.add_route(self.router, "POST", path, handler)
    return self
end

function Server:put(path, handler)
    router_lib.add_route(self.router, "PUT", path, handler)
    return self
end

function Server:patch(path, handler)
    router_lib.add_route(self.router, "PATCH", path, handler)
    return self
end

function Server:delete(path, handler)
    router_lib.add_route(self.router, "DELETE", path, handler)
    return self
end

function Server:options(path, handler)
    router_lib.add_route(self.router, "OPTIONS", path, handler)
    return self
end

function Server:head(path, handler)
    router_lib.add_route(self.router, "HEAD", path, handler)
    return self
end

-- Define prefixo global
function Server:prefix(p)
    router_lib.set_prefix(self.router, p)
    return self
end

-- Limpa prefixo
function Server:clear_prefix()
    router_lib.clear_prefix(self.router)
    return self
end

-- Grupo de rotas com prefixo
function Server:group(prefix, fn)
    router_lib.push_prefix(self.router, prefix)
    local ok, err = pcall(fn, self)
    router_lib.pop_prefix(self.router)
    
    if not ok then
        error(err)
    end
    
    return self
end

-- Executa cadeia de middlewares
local function run_middlewares(middlewares, ctx, index)
    index = index or 1
    
    if index > #middlewares then
        return true
    end
    
    local middleware = middlewares[index]
    
    local next_fn = function()
        return run_middlewares(middlewares, ctx, index + 1)
    end
    
    local ok, result = pcall(middleware, ctx, next_fn)
    
    if not ok then
        return false, result
    end
    
    -- Se middleware retornou false, parar a cadeia
    if result == false then
        return false  -- Retorna false para indicar que parou
    end
    
    -- Continua
    return true
end

-- Processa requisição
function Server:_handle_request(req, res)
    -- Cria context preliminar para middlewares
    local parsed_url = req.url and url.parse(req.url) or {}
    local path = parsed_url.pathname or "/"
    
    local ctx = context_lib.new(req, res, {
        handler = nil,
        params = {},
        route_path = nil
    })
    
    -- Executa middlewares ANTES de procurar rotas (para arquivos estáticos)
    if #self.middlewares > 0 then
        local ok, err = run_middlewares(self.middlewares, ctx)
        
        if not ok then
            if self.error_handler then
                pcall(self.error_handler, ctx, err)
            else
                response_lib.error(res, 500, "middleware error", tostring(err))
            end
            return
        end
        
        -- Se middleware parou (retornou false), resposta foi finalizada
        if err == false or res.finished then
            return
        end
    end
    
    -- Busca rota (agora após middlewares)
    local handler, params, route_path = router_lib.match_route(
        self.router, 
        req.method, 
        path
    )
    
    -- Atualiza context com informações da rota
    ctx.handler = handler
    ctx.params = params
    ctx.route_path = route_path
    
    -- Handler 404 se rota não encontrada
    if not handler then
        -- Verifica se já foi enviada uma resposta (ex: arquivo estático)
        if res.finished then
            return
        end
        
        if self.not_found_handler then
            local ok, err = pcall(self.not_found_handler, ctx)
            if not ok then
                response_lib.error(res, 500, "error in not_found handler", err)
            end
        else
            response_lib.error(res, 404, "route not found", {
                method = ctx.method,
                path = ctx.path
            })
        end
        return
    end
    
    -- Lê body se necessário
    request_lib.read_body(req, self.config.max_body_size, function(raw, parsed, err)
        context_lib.set_body(ctx, raw, parsed, err)
        
        -- Executa handler da rota
        local ok, result = pcall(handler, ctx)
        
        if not ok then
            if self.error_handler then
                pcall(self.error_handler, ctx, result)
            else
                response_lib.error(res, 500, "handler error", tostring(result))
            end
            return
        end
        
        -- Se handler retornou algo e resposta ainda não foi enviada
        if result ~= nil and not res.finished then
            if type(result) == "table" then
                response_lib.json(res, 200, result)
            else
                response_lib.text(res, 200, tostring(result))
            end
        end
    end)
end

-- Inicia servidor
function Server:listen(port, host)
    host = host or "0.0.0.0"
    port = port or 8080
    
    http.createServer(function(req, res)
        self:_handle_request(req, res)
    end):listen(port, host)
    
    print(string.format("🌙 Crescent server listening on http://%s:%d", host, port))
    
    return self
end

-- Configura opção do servidor
function Server:set(key, value)
    self.config[key] = value
    return self
end

return Server
