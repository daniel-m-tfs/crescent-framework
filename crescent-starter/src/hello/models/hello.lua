-- src/hello/models/hello.lua
-- Model/Entity para Hello

local Hello = {}
Hello.__index = Hello

function Hello.new(data)
    local self = setmetatable({}, Hello)
    self.id = data.id
    self.created_at = data.created_at or os.time()
    self.updated_at = data.updated_at
    return self
end

function Hello:validate()
    -- Adicione validações aqui
    if not self.id then
        return false, "ID é obrigatório"
    end
    return true
end

function Hello:toTable()
    return {
        id = self.id,
        created_at = self.created_at,
        updated_at = self.updated_at
    }
end

return Hello
