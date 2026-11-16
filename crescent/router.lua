local Router = {}
Router.__index = Router

local METHODS = { "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD" }

local function escape_pattern(value)
    return (value:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function decode_component(value)
    if value:find("%%[^0-9a-fA-F]", 1) or value:find("%%.$") then
        return nil
    end
    local invalid = false
    local decoded = value:gsub("%%([0-9a-fA-F][0-9a-fA-F])", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    if decoded:find("%%") or decoded:find("%z") then invalid = true end
    return invalid and nil or decoded
end

local function clone(items)
    local copy = {}
    for index, value in ipairs(items) do copy[index] = value end
    return copy
end

local function join_paths(prefix, path)
    if prefix == "" then return path end
    if prefix == "/" then return path end
    return prefix:gsub("/$", "") .. "/" .. path:gsub("^/", "")
end

local function compile(path)
    local segments = {}
    for segment in path:gsub("^/", ""):gmatch("[^/]+") do
        segments[#segments + 1] = segment
    end

    local all_names = {}
    local priority = 0
    for _, segment in ipairs(segments) do
        local name = segment:match("^%{([_%a][_%w]*)%}$")
        local optional_name = segment:match("^%{([_%a][_%w]*)%?%}$")
        local wildcard_name = segment:match("^%{([_%a][_%w]*)%*%}$")
        if name then
            all_names[#all_names + 1] = name
            priority = priority + 2
        elseif optional_name then
            all_names[#all_names + 1] = optional_name
            priority = priority + 1
        elseif wildcard_name then
            all_names[#all_names + 1] = wildcard_name
        else
            priority = priority + 10
        end
    end

    local function build(index, parts, names, variants)
        if index > #segments then
            local pattern = "^" .. (#parts > 0 and table.concat(parts) or "/") .. "$"
            variants[#variants + 1] = { pattern = pattern, names = names }
            return
        end

        local segment = segments[index]
        local required_name = segment:match("^%{([_%a][_%w]*)%}$")
        local optional_name = segment:match("^%{([_%a][_%w]*)%?%}$")
        local wildcard_name = segment:match("^%{([_%a][_%w]*)%*%}$")

        if required_name then
            local next_parts = clone(parts)
            local next_names = clone(names)
            next_parts[#next_parts + 1] = "/([^/]+)"
            next_names[#next_names + 1] = required_name
            build(index + 1, next_parts, next_names, variants)
            return
        end

        if optional_name then
            local with_value_parts = clone(parts)
            local with_value_names = clone(names)
            with_value_parts[#with_value_parts + 1] = "/([^/]+)"
            with_value_names[#with_value_names + 1] = optional_name
            build(index + 1, with_value_parts, with_value_names, variants)

            local without_value_parts = clone(parts)
            local without_value_names = clone(names)
            build(index + 1, without_value_parts, without_value_names, variants)
            return
        end

        if wildcard_name then
            assert(index == #segments, "wildcard parameter must be the final route segment")
            local next_parts = clone(parts)
            local next_names = clone(names)
            next_parts[#next_parts + 1] = "/(.+)"
            next_names[#next_names + 1] = wildcard_name
            build(index + 1, next_parts, next_names, variants)
            return
        end

        local next_parts = clone(parts)
        next_parts[#next_parts + 1] = "/" .. escape_pattern(segment)
        build(index + 1, next_parts, names, variants)
    end

    local variants = {}
    build(1, {}, {}, variants)
    return variants, all_names, priority
end

function Router.new()
    local routes = {}
    for _, method in ipairs(METHODS) do routes[method] = {} end
    return setmetatable({ routes = routes, names = {}, order = 0, prefix = "" }, Router)
end

function Router:add(method, path, action, name)
    assert(self.routes[method], "unsupported HTTP method: " .. tostring(method))
    assert(type(path) == "string" and path:sub(1, 1) == "/", "route path must start with /")
    assert(type(action) == "function", "route action must be a function")
    if name ~= nil then
        assert(type(name) == "string" and name ~= "", "route name must be a non-empty string")
        assert(not self.names[name], "route name already registered: " .. name)
    end
    path = join_paths(self.prefix, path)
    local variants, names, priority = compile(path)
    self.order = self.order + 1
    local has_optional = path:find("%{[%w_]+%?%}") ~= nil
    self.routes[method][#self.routes[method] + 1] = {
        path = path,
        patterns = variants,
        names = names,
        action = action,
        order = self.order,
        optional = has_optional,
        priority = priority,
        name = name,
    }
    if name then self.names[name] = path end
    table.sort(self.routes[method], function(left, right)
        if left.priority ~= right.priority then return left.priority > right.priority end
        if left.optional ~= right.optional then return left.optional == false end
        return left.order < right.order
    end)
    return self
end

function Router:group(prefix, callback)
    assert(type(prefix) == "string" and prefix:sub(1, 1) == "/", "group prefix must start with /")
    assert(type(callback) == "function", "group callback must be a function")
    local previous_prefix = self.prefix
    self.prefix = join_paths(previous_prefix, prefix)
    local ok, err = pcall(callback, self)
    self.prefix = previous_prefix
    if not ok then error(err, 0) end
    return self
end

function Router:find(name)
    return self.names[name]
end

function Router:match(method, path)
    for _, route in ipairs(self.routes[method] or {}) do
        for _, variant in ipairs(route.patterns or {}) do
            local captures = { path:match(variant.pattern) }
            if #captures > 0 then
                local params = {}
                for _, name in ipairs(route.names) do params[name] = nil end
                for index, name in ipairs(variant.names) do
                    local value = decode_component(captures[index])
                    if not value then return nil, "invalid route encoding" end
                    params[name] = value
                end
                return route.action, params, route.path
            end
        end
    end
end

function Router:allowed_methods(path)
    local allowed = {}
    for _, method in ipairs(METHODS) do
        local action = self:match(method, path)
        if action then allowed[#allowed + 1] = method end
    end
    return allowed
end

return Router
