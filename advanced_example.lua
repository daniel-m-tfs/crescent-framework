-- advanced_example.lua
-- Exemplo avançado do Crescent Framework com múltiplas features

local crescent = require("crescent")
local json = require("json")

-- Configuração
local config = require("config.development")

-- ============ SIMULAÇÃO DE DATABASE ============
local db = {
    users = {
        {id = 1, name = "Admin User", email = "admin@example.com", role = "admin"},
        {id = 2, name = "John Doe", email = "john@example.com", role = "user"},
        {id = 3, name = "Jane Smith", email = "jane@example.com", role = "user"}
    },
    posts = {
        {id = 1, user_id = 2, title = "First Post", content = "Hello World", created_at = 1704448800},
        {id = 2, user_id = 2, title = "Second Post", content = "Lua is awesome", created_at = 1704535200},
        {id = 3, user_id = 3, title = "Jane's Post", content = "Learning Crescent", created_at = 1704621600}
    },
    next_user_id = 4,
    next_post_id = 4
}

-- ============ HELPERS ============

-- Busca usuário por ID
local function find_user_by_id(id)
    id = tonumber(id)
    for _, user in ipairs(db.users) do
        if user.id == id then
            return user
        end
    end
    return nil
end

-- Busca posts de um usuário
local function find_posts_by_user(user_id)
    user_id = tonumber(user_id)
    local result = {}
    for _, post in ipairs(db.posts) do
        if post.user_id == user_id then
            table.insert(result, post)
        end
    end
    return result
end

-- Valida email
local function is_valid_email(email)
    return email and email:match("^[%w%._%+%-]+@[%w%.%-]+%.[%a]+$") ~= nil
end

-- ============ AUTENTICAÇÃO ============

-- Tokens válidos (em produção, use JWT ou DB)
local valid_tokens = {
    ["admin-token-123"] = {id = 1, role = "admin"},
    ["user-token-456"] = {id = 2, role = "user"},
    ["jane-token-789"] = {id = 3, role = "user"}
}

-- Middleware de autenticação
local auth_middleware = crescent.middleware.auth.bearer(function(token, ctx)
    local user = valid_tokens[token]
    if user then
        return true, user
    end
    return false, "invalid or expired token"
end)

-- Middleware de autorização (admin only)
local function admin_only()
    return function(ctx, next)
        local token = ctx.getBearer()
        local user = valid_tokens[token]
        
        if not user or user.role ~= "admin" then
            return ctx.error(403, "forbidden", "admin access required")
        end
        
        ctx.state.user = user
        
        if next then
            return next()
        end
        return true
    end
end

-- ============ VALIDAÇÃO ============

-- Middleware de validação de body
local function validate_json_body(required_fields)
    return function(ctx, next)
        if not ctx.body then
            return ctx.error(400, "invalid json body")
        end
        
        for _, field in ipairs(required_fields or {}) do
            if not ctx.body[field] then
                return ctx.error(400, "missing required field: " .. field)
            end
        end
        
        if next then
            return next()
        end
        return true
    end
end

-- ============ APLICAÇÃO ============

local app = crescent.new()

-- Configurações
app:set("max_body_size", config.server.max_body_size)

-- ============ MIDDLEWARES GLOBAIS ============

-- Logger detalhado
app:use(crescent.middleware.logger.detailed())

-- CORS
app:use(crescent.middleware.cors.default())

-- Security headers
app:use(crescent.middleware.security.headers())

-- Path traversal protection
app:use(crescent.middleware.security.path_traversal())

-- Body size limit
app:use(crescent.middleware.security.body_size_limit(5 * 1024 * 1024))

-- ============ ROTAS PÚBLICAS ============

-- Health check
app:get("/health", function(ctx)
    return ctx.json(200, {
        status = "healthy",
        timestamp = os.time(),
        uptime = os.clock(),
        version = crescent.VERSION
    })
end)

-- Root
app:get("/", function(ctx)
    return ctx.json(200, {
        name = "Crescent Framework - Advanced Example",
        version = crescent.VERSION,
        endpoints = {
            health = "/health",
            docs = "/docs",
            users = "/api/users",
            posts = "/api/posts",
            auth_example = "/api/profile (requires Bearer token)"
        }
    })
end)

-- Docs
app:get("/docs", function(ctx)
    return ctx.json(200, {
        authentication = {
            type = "Bearer Token",
            header = "Authorization: Bearer <token>",
            valid_tokens = {
                admin = "admin-token-123",
                user = "user-token-456",
                jane = "jane-token-789"
            }
        },
        endpoints = {
            {method = "GET", path = "/api/users", auth = false, description = "List all users"},
            {method = "GET", path = "/api/users/{id}", auth = false, description = "Get user by ID"},
            {method = "POST", path = "/api/users", auth = true, role = "admin", description = "Create user"},
            {method = "GET", path = "/api/users/{id}/posts", auth = false, description = "Get user posts"},
            {method = "GET", path = "/api/posts", auth = false, description = "List all posts"},
            {method = "POST", path = "/api/posts", auth = true, description = "Create post"},
            {method = "GET", path = "/api/profile", auth = true, description = "Get current user profile"},
            {method = "GET", path = "/admin/stats", auth = true, role = "admin", description = "Get stats"}
        }
    })
end)

-- ============ API v1 ============

app:group("/api", function(app)
    
    -- ============ USERS ============
    
    -- List all users
    app:get("/users", function(ctx)
        -- Paginação
        local page = tonumber(ctx.query.page) or 1
        local limit = tonumber(ctx.query.limit) or 10
        local offset = (page - 1) * limit
        
        -- Simula paginação
        local users = {}
        for i = offset + 1, math.min(offset + limit, #db.users) do
            if db.users[i] then
                table.insert(users, {
                    id = db.users[i].id,
                    name = db.users[i].name,
                    email = db.users[i].email
                })
            end
        end
        
        return ctx.json(200, {
            data = users,
            pagination = {
                page = page,
                limit = limit,
                total = #db.users
            }
        })
    end)
    
    -- Get user by ID
    app:get("/users/{id}", function(ctx)
        local user = find_user_by_id(ctx.params.id)
        
        if not user then
            return ctx.error(404, "user not found")
        end
        
        return ctx.json(200, {
            id = user.id,
            name = user.name,
            email = user.email
        })
    end)
    
    -- Create user (admin only)
    app:post("/users", function(ctx)
        -- Validação inline (poderia usar middleware)
        local token = ctx.getBearer()
        local auth_user = valid_tokens[token]
        
        if not auth_user or auth_user.role ~= "admin" then
            return ctx.error(403, "admin access required")
        end
        
        if not ctx.body or not ctx.body.name or not ctx.body.email then
            return ctx.error(400, "name and email are required")
        end
        
        if not is_valid_email(ctx.body.email) then
            return ctx.error(400, "invalid email format")
        end
        
        -- Cria usuário
        local new_user = {
            id = db.next_user_id,
            name = ctx.body.name,
            email = ctx.body.email,
            role = ctx.body.role or "user"
        }
        
        table.insert(db.users, new_user)
        db.next_user_id = db.next_user_id + 1
        
        return ctx.json(201, {
            id = new_user.id,
            name = new_user.name,
            email = new_user.email,
            role = new_user.role
        })
    end)
    
    -- Get user's posts
    app:get("/users/{id}/posts", function(ctx)
        local user = find_user_by_id(ctx.params.id)
        
        if not user then
            return ctx.error(404, "user not found")
        end
        
        local posts = find_posts_by_user(user.id)
        
        return ctx.json(200, {
            user = {
                id = user.id,
                name = user.name
            },
            posts = posts,
            count = #posts
        })
    end)
    
    -- ============ POSTS ============
    
    -- List all posts
    app:get("/posts", function(ctx)
        -- Filtro por user_id
        local user_id = ctx.query.user_id
        
        local posts = db.posts
        if user_id then
            posts = find_posts_by_user(user_id)
        end
        
        return ctx.json(200, {
            data = posts,
            count = #posts
        })
    end)
    
    -- Create post (authenticated users)
    app:post("/posts", function(ctx)
        local token = ctx.getBearer()
        local user = valid_tokens[token]
        
        if not user then
            return ctx.error(401, "authentication required")
        end
        
        if not ctx.body or not ctx.body.title or not ctx.body.content then
            return ctx.error(400, "title and content are required")
        end
        
        local new_post = {
            id = db.next_post_id,
            user_id = user.id,
            title = ctx.body.title,
            content = ctx.body.content,
            created_at = os.time()
        }
        
        table.insert(db.posts, new_post)
        db.next_post_id = db.next_post_id + 1
        
        return ctx.json(201, new_post)
    end)
    
    -- ============ PROFILE (Authenticated) ============
    
    app:get("/profile", function(ctx)
        local token = ctx.getBearer()
        local user = valid_tokens[token]
        
        if not user then
            return ctx.error(401, "authentication required")
        end
        
        local full_user = find_user_by_id(user.id)
        local posts = find_posts_by_user(user.id)
        
        return ctx.json(200, {
            user = full_user,
            posts_count = #posts,
            token_info = {
                authenticated = true,
                role = user.role
            }
        })
    end)
    
end)

-- ============ ADMIN ROUTES ============

app:group("/admin", function(app)
    
    -- Stats (admin only)
    app:get("/stats", function(ctx)
        local token = ctx.getBearer()
        local user = valid_tokens[token]
        
        if not user or user.role ~= "admin" then
            return ctx.error(403, "admin access required")
        end
        
        return ctx.json(200, {
            users = {
                total = #db.users,
                by_role = {
                    admin = 1,
                    user = #db.users - 1
                }
            },
            posts = {
                total = #db.posts,
                recent = db.posts[#db.posts]
            },
            system = {
                uptime = os.clock(),
                memory = collectgarbage("count") .. " KB"
            }
        })
    end)
    
end)

-- ============ ERROR HANDLERS ============

app:on_not_found(function(ctx)
    return ctx.json(404, {
        error = "endpoint not found",
        method = ctx.method,
        path = ctx.path,
        suggestion = "check /docs for available endpoints"
    })
end)

app:on_error(function(ctx, error)
    print("ERROR:", error)
    
    return ctx.json(500, {
        error = "internal server error",
        detail = tostring(error),
        request_id = os.time()
    })
end)

-- ============ INICIA SERVIDOR ============

print("\n🌙 Crescent Framework - Advanced Example")
print("========================================")
print("\n📚 Documentação: http://localhost:" .. config.server.port .. "/docs")
print("\n🔑 Tokens de teste:")
print("   Admin: admin-token-123")
print("   User:  user-token-456")
print("   Jane:  jane-token-789")
print("\n💡 Exemplos de uso:")
print("   curl http://localhost:" .. config.server.port .. "/health")
print("   curl http://localhost:" .. config.server.port .. "/docs")
print("   curl http://localhost:" .. config.server.port .. "/api/users")
print("   curl http://localhost:" .. config.server.port .. "/api/profile -H 'Authorization: Bearer user-token-456'")
print("\n")

app:listen(config.server.port, config.server.host)

require('luvit').run()
