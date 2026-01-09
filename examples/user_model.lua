-- examples/user_model.lua
-- Exemplo de Model usando o ORM Crescent

local Model = require("crescent.database.model")
local QB = require("crescent.database.query_builder")

-- Define o User Model
local User = Model:extend({
    table = "users",
    primary_key = "id",
    
    -- Mass assignment protection
    fillable = {"name", "email", "password", "active"},
    hidden = {"password"}, -- Não retorna em toArray()
    
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

-- ==========================
-- EXEMPLOS DE USO
-- ==========================

--[[
-- 1. CRUD básico
local user = User:create({name = "João", email = "joao@test.com", password = "secret"})
local found = User:find(1)
found:update({name = "João Silva"})
found:delete()

-- 2. Busca com QueryBuilder
local active_users = User:query()
    :where("active", true)
    :where("age", ">", 18)
    :orderBy("name", "ASC")
    :limit(10)
    :get()

-- 3. Busca com scopes
local recent = User:scopeRecent(7):get()

-- 4. Query raw SEGURA (com bindings)
local results = User:raw("SELECT * FROM users WHERE name LIKE ? AND age > ?", {"%João%", 18})

-- 5. Query raw complexa
local stats = User:raw([[
    SELECT 
        DATE(created_at) as date,
        COUNT(*) as total
    FROM users
    WHERE created_at > ?
    GROUP BY DATE(created_at)
    ORDER BY date DESC
]]--, {"2026-01-01"})

-- 6. QueryBuilder direto (sem Model)
local QB = require("crescent.database.query_builder")
local all_users = QB.table("users")
    :select("id", "name", "email")
    :where("deleted_at", "IS NULL")
    :get()

-- 7. Serialização para JSON
local user = User:find(1)
local json_data = user:toArray()  -- Remove propriedades internas
-- Retorna: {id = 1, name = "João", email = "joao@test.com", created_at = "...", updated_at = "..."}
-- Note que "password" NÃO aparece (está em hidden)
--]]

return User
