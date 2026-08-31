-- cli/templates.lua
-- Templates de código para o crescent-cli (make:controller, make:service, etc)

local M = {}

-- Capitaliza primeira letra
function M.capitalize(str)
    return str:gsub("^%l", string.upper)
end

-- Converte para snake_case
function M.to_snake_case(str)
    return str:gsub("(%u)", "_%1"):lower():gsub("^_", "")
end

M.migration = function(name)
    local timestamp = os.date("%Y%m%d%H%M%S")
    local filename = timestamp .. "_" .. name .. ".lua"
    
    -- Extrai nome da tabela do padrão create_xxx_table ou add_xxx_to_yyy
    local table_name = "example"
    
    -- Padrão: create_products_table -> products
    if name:match("^create_(.+)_table$") then
        table_name = name:match("^create_(.+)_table$")
    -- Padrão: add_column_to_users -> users
    elseif name:match("_to_(.+)$") then
        table_name = name:match("_to_(.+)$")
    -- Padrão: drop_products_table -> products
    elseif name:match("^drop_(.+)_table$") then
        table_name = name:match("^drop_(.+)_table$")
    -- Padrão: update_products_table -> products
    elseif name:match("^update_(.+)_table$") then
        table_name = name:match("^update_(.+)_table$")
    end
    
    local content = [[-- migrations/]] .. filename .. "\n" .. [[
-- Migration: ]] .. name .. "\n\n" .. [[
local Migration = {}

-- Executa a migration (criar tabelas, adicionar colunas, etc)
function Migration:up()
    return ]].. "[[" .. [[

        CREATE TABLE IF NOT EXISTS ]] .. table_name .. [[ (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]] .. "]]" .. [[

end

-- Desfaz a migration (remover tabelas, colunas, etc)
function Migration:down()
    return ]] .. "[[" .. [[

        DROP TABLE IF EXISTS ]] .. table_name .. [[;
    ]] .. "]]" .. [[

end

return Migration
]]
    
    return filename, content
end

M.controller = function(name, module_name)
    local class_name = M.capitalize(name) .. "Controller"
    local service_name = M.to_snake_case(name)
    return string.format([[-- src/%s/controllers/%s.lua
-- Controller para %s

local service = require("src.%s.services.%s")
local %s = {}

function %s:index(ctx)
    local result = service:getAll()
    return ctx.json(200, result)
end

function %s:show(ctx)
    local id = ctx.params.id
    local result = service:getById(id)
    
    if result then
        return ctx.json(200, result)
    end

    return ctx.json(404, { error = "Not found" })
end

function %s:create(ctx)
    local body = ctx.body or {}
    local result = service:create(body)
    
    return ctx.json(201, result)
end

function %s:update(ctx)
    local id = ctx.params.id
    local body = ctx.body or {}
    local result = service:update(id, body)
    
    if result then
        return ctx.json(200, result)
    else
        return ctx.json(404, { error = "Not found" })
    end
end

function %s:delete(ctx)
    local id = ctx.params.id
    local success = service:delete(id)
    
    if success then
        return ctx.no_content()
    else
        return ctx.json(404, { error = "Not found" })
    end
end

return %s
]], module_name, service_name, name, 
    module_name, service_name, class_name,
    class_name, class_name, class_name, class_name, class_name, class_name)
end

M.service = function(name, module_name)
    local class_name = M.capitalize(name) .. "Service"
    local model_name = M.capitalize(name)
    local model_file = M.to_snake_case(name)
    return string.format([[-- src/%s/services/%s.lua
-- Service para lógica de negócio de %s

local %s = {}
local %s = require("src.%s.models.%s")

function %s:getAll()
    return %s:all()
end

function %s:getById(id)
    return %s:find(id)
end

function %s:create(body)
   return %s:create(body)
end

function %s:update(id, body)
    local %s = %s:find(id)
    if %s then
        %s:update(body)
        return %s
    end
    return nil
end

function %s:delete(id)
    local %s = %s:find(id)
    if %s then
        %s:delete()
        return true
    end
    return false
end

return %s
]], module_name, M.to_snake_case(name), name,
    class_name, model_name, module_name, model_file,
    class_name, model_name,
    class_name, model_name,
    class_name, model_name,
    class_name, M.to_snake_case(name), model_name, M.to_snake_case(name),
    M.to_snake_case(name), M.to_snake_case(name),
    class_name, M.to_snake_case(name), model_name, M.to_snake_case(name),
    M.to_snake_case(name),
    class_name)
end

M.model = function(name, module_name)
    local class_name = M.capitalize(name)
    local table_name = M.to_snake_case(name)
    return string.format([[-- src/%s/models/%s.lua
-- Model para %s usando Active Record ORM

local Model = require("crescent.database.model")

local %s = Model:extend({
    table = "%s",
    primary_key = "id",
    timestamps = true,
    soft_deletes = false,
    
    fillable = {
        -- Adicione aqui os campos que podem ser preenchidos em massa
        "name",
    },
    
    hidden = {
        -- Campos que não devem aparecer em JSON/serialização
        -- "password"
    },

    guarded = {
        -- Campos protegidos contra mass assignment
        -- "id", "created_at", "updated_at"
    },
    
    validates = {
        -- Adicione validações aqui
        name = {required = true, min = 3, max = 255},
    },
    
    relations = {
        -- Defina relações aqui
        -- posts = {type = "hasMany", model = "Post", foreign_key = "user_id"},
        -- profile = {type = "hasOne", model = "Profile", foreign_key = "user_id"},
    }
})

-- Métodos personalizados do model
-- function %s:customMethod()
--     -- Seu código aqui
-- end

return %s
]], module_name, table_name, class_name,
    class_name, table_name, class_name, class_name)
end

M.routes = function(name, module_name)
    local snake_name = M.to_snake_case(name)
    return string.format([[-- src/%s/routes/%s.lua
-- Rotas para %s
-- prefix definido em %s/init.lua

local controller = require("src.%s.controllers.%s")

return function(app, prefix)
    prefix = prefix or "/%s"
    
    -- CRUD completo
    app:get(prefix, function(ctx)
        return controller:index(ctx)
    end)
    
    app:get(prefix .. "/{id}", function(ctx)
        return controller:show(ctx)
    end)
    
    app:post(prefix, function(ctx)
        return controller:create(ctx)
    end)
    
    app:put(prefix .. "/{id}", function(ctx)
        return controller:update(ctx)
    end)
    
    app:delete(prefix .. "/{id}", function(ctx)
        return controller:delete(ctx)
    end)
end
]], module_name, snake_name, name, snake_name,
    module_name, snake_name, snake_name)
end

M.module = function(name)
    local module_name = M.to_snake_case(name)
    local snake_name = M.to_snake_case(name)
    return string.format([[-- src/%s/init.lua
-- Módulo %s - Agrupa controllers, services e rotas

local Module = {}

function Module.register(app)
    -- Registra rotas do módulo
    local routes = require("src.%s.routes.%s")
    routes(app, "/%s")
    
    print("✓ Módulo %s carregado")
end

return Module
]], module_name, M.capitalize(name),
    module_name, snake_name, snake_name, M.capitalize(name))
end


return M
