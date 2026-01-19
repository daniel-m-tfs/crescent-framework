-- crescent/core/router.lua
-- Sistema de roteamento HTTP com suporte a parâmetros dinâmicos

local path_utils = require("crescent.utils.path")

local M = {}

-- Métodos HTTP suportados
local METHODS = {"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"}

-- Cria nova instância do router
function M.new()
    local routes = {}
    for _, method in ipairs(METHODS) do
        routes[method] = {}
    end
    
    return {
        routes = routes,
        _base_prefix = "",
        _prefix_stack = {}
    }
end

-- Adiciona uma rota
function M.add_route(router, method, path, handler)
    if type(handler) ~= "function" then
        error("Handler must be a function")
    end
    
    -- Valida path
    if not path_utils.is_safe(path) then
        error("Unsafe path: " .. tostring(path))
    end
    
    -- Calcula prefixo atual
    local prefix = M.get_current_prefix(router)
    local fullPath = path_utils.join(prefix, path)
    fullPath = path_utils.normalize(fullPath)
    
    -- Compila path
    local pattern, names = path_utils.compile(fullPath)
    
    table.insert(router.routes[method], {
        pattern = pattern,
        names = names,
        handler = handler,
        path = fullPath
    })
end

-- Busca rota correspondente
function M.match_route(router, method, path)
    local list = router.routes[method] or {}
    
    for _, route in ipairs(list) do
        local caps = {path:match(route.pattern)}
        if #caps > 0 then
            local params = {}
            for i, name in ipairs(route.names) do
                local v = caps[i]
                if v == "" then
                    v = nil
                end
                params[name] = v
            end
            return route.handler, params, route.path
        end
    end
    
    return nil
end

-- Define prefixo global
function M.set_prefix(router, prefix)
    router._base_prefix = prefix or ""
end

-- Limpa prefixo global
function M.clear_prefix(router)
    router._base_prefix = ""
end

-- Adiciona prefixo temporário (grupo)
function M.push_prefix(router, prefix)
    table.insert(router._prefix_stack, prefix or "")
end

-- Remove prefixo temporário
function M.pop_prefix(router)
    table.remove(router._prefix_stack)
end

-- Calcula prefixo atual (base + stack)
function M.get_current_prefix(router)
    local acc = router._base_prefix or ""
    for _, p in ipairs(router._prefix_stack) do
        acc = path_utils.join(acc, p)
    end
    return acc
end

return M
