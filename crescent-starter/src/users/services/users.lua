-- src/users/services/users.lua
-- Service para lógica de negócio de Users

local UsersService = {}

-- Simulação de banco de dados (substitua por ORM real)
local data = {}
local next_id = 1

function UsersService:getAll()
    return {
        success = true,
        data = data,
        message = "Lista de Users"
    }
end

function UsersService:getById(id)
    local search_id = tonumber(id) or id
    for _, item in ipairs(data) do
        if item.id == search_id then
            return {
                success = true,
                data = item
            }
        end
    end
    return nil
end

function UsersService:create(body)
    local item = {
        id = next_id,
        created_at = os.time()
    }
    
    -- Copia dados do body
    for k, v in pairs(body) do
        item[k] = v
    end
    
    table.insert(data, item)
    next_id = next_id + 1
    
    return {
        success = true,
        data = item,
        message = "Users criado com sucesso"
    }
end

function UsersService:update(id, body)
    local search_id = tonumber(id) or id
    for i, item in ipairs(data) do
        if item.id == search_id then
            for k, v in pairs(body) do
                item[k] = v
            end
            item.updated_at = os.time()
            return {
                success = true,
                data = item,
                message = "Users atualizado"
            }
        end
    end
    return nil
end

function UsersService:delete(id)
    local search_id = tonumber(id) or id
    for i, item in ipairs(data) do
        if item.id == search_id then
            table.remove(data, i)
            return true
        end
    end
    return false
end

return UsersService
