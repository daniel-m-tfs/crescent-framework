-- src/hello/services/hello.lua
-- Service para lógica de negócio de Hello

local HelloService = {}

-- Simulação de banco de dados (substitua por ORM real)
local data = {}
local next_id = 1

function HelloService:getAll()
    return {
        success = true,
        data = data,
        message = "Lista de Hello"
    }
end

function HelloService:getById(id)
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

function HelloService:create(body)
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
        message = "Hello criado com sucesso"
    }
end

function HelloService:update(id, body)
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
                message = "Hello atualizado"
            }
        end
    end
    return nil
end

function HelloService:delete(id)
    local search_id = tonumber(id) or id
    for i, item in ipairs(data) do
        if item.id == search_id then
            table.remove(data, i)
            return true
        end
    end
    return false
end

return HelloService
