-- src/users/models/users.lua
-- Model/Entity para Users

local Users = {}
Users.__index = Users

function Users.new(data)
    local self = setmetatable({}, Users)
    self.id = data.id
    self.created_at = data.created_at or os.time()
    self.updated_at = data.updated_at
    return self
end

function Users:validate()
    -- Adicione validações aqui
    if not self.id then
        return false, "ID é obrigatório"
    end
    return true
end

function Users:toTable()
    return {
        id = self.id,
        created_at = self.created_at,
        updated_at = self.updated_at
    }
end

return Users
