-- src/users/models/users.lua
-- Model para Users usando Active Record ORM

local Model = require("crescent.database.model")

local Users = Model:extend({
    table = "users",
    primary_key = "id",
    timestamps = true,
    soft_deletes = false,
    
    fillable = {
        -- Adicione aqui os campos que podem ser preenchidos em massa
        -- "name", "email", etc.
    },
    
    hidden = {
        -- Campos que não devem aparecer em JSON/serialização
        -- "password", "token", etc.
    },
    
    validates = {
        -- Adicione validações aqui
        -- name = {required = true, min = 3, max = 255},
        -- email = {required = true, email = true, unique = true},
    },
    
    relations = {
        -- Defina relações aqui
        -- posts = {type = "hasMany", model = "Post", foreign_key = "user_id"},
        -- profile = {type = "hasOne", model = "Profile", foreign_key = "user_id"},
    }
})

-- Métodos personalizados do model
-- function Users:customMethod()
--     -- Seu código aqui
-- end

return Users
