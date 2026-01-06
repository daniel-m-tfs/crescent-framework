-- examples/user_model.lua
-- Exemplo de Model usando o ORM Crescent

local Model = require("crescent.database.model")

-- Define o User Model
local User = Model:extend({
    table = "users",
    primary_key = "id",
    
    -- Mass assignment protection
    fillable = {"name", "email", "password", "active"},
    hidden = {"password"}, -- Não retorna em toTable()
    
    -- Timestamps automáticos (created_at, updated_at)
    timestamps = true,
    
    -- Soft deletes (deleted_at)
    soft_deletes = false,
    
    -- Validações
    validates = {
        name = {
            required = true,
            min_length = 3,
            max_length = 100
        },
        email = {
            required = true,
            email = true,
            unique = true
        },
        password = {
            required = true,
            min_length = 6
        }
    },
    
    -- Hooks
    before_save = function(user)
        -- Hash password antes de salvar
        if user._attributes.password and not user._attributes.password:match("^%$2") then
            -- user._attributes.password = bcrypt(user._attributes.password)
            print("🔒 Hashing password...")
        end
    end,
    
    after_create = function(user)
        print("✅ Usuário criado:", user._attributes.name)
    end,
    
    -- Relações
    relations = {
        posts = function(self)
            local Post = require("examples.post_model")
            return self:hasMany(Post, "user_id")
        end,
        
        profile = function(self)
            local Profile = require("examples.profile_model")
            return self:hasOne(Profile, "user_id")
        end
    }
})

-- Scopes personalizados
function User:scopeActive()
    return self:query():where("active", true)
end

function User:scopeRecent(days)
    local date = os.date("%Y-%m-%d", os.time() - (days * 86400))
    return self:query():where("created_at", ">=", date)
end

return User
