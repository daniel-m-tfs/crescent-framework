-- Relation resolution and eager loading. Every relation is loaded for a whole
-- set of parent models with ONE `WHERE key IN (...)` query (no N+1).
local Relations = {}

local unpack_values = table.unpack or unpack

local IRREGULAR_PLURALS = {
    people = "person", men = "man", women = "woman", children = "child",
    feet = "foot", teeth = "tooth", mice = "mouse", geese = "goose",
}

-- Convention heuristic for default foreign keys, not a full inflector:
-- users -> user, categories -> category, addresses -> address, people -> person.
function Relations.singularize(word)
    if IRREGULAR_PLURALS[word] then return IRREGULAR_PLURALS[word] end
    if word:match("ies$") then return word:sub(1, -4) .. "y" end
    if word:match("[sx]es$") or word:match("[cs]hes$") then return word:sub(1, -3) end
    if word:match("s$") and not word:match("ss$") then return word:sub(1, -2) end
    return word
end

function Relations.default_foreign_key(table_name)
    local base = tostring(table_name):match("([^%.]+)$")
    return Relations.singularize(base) .. "_id"
end

local VALID_TYPES = { has_many = true, has_one = true, belongs_to = true }

-- `model` may be the model table, a module name ("src.blog.models.post") or a
-- function returning the model (handy for mutually-referencing models).
local function resolve_model(reference)
    if type(reference) == "string" then return require(reference) end
    if type(reference) == "function" then return reference() end
    return reference
end

function Relations.definition(class, name)
    local definition = class.relations and class.relations[name]
    if type(definition) ~= "table" then return nil, "unknown relation: " .. tostring(name) end
    if not VALID_TYPES[definition.type] then
        return nil, "relation " .. name .. " has invalid type: " .. tostring(definition.type)
    end
    local related = resolve_model(definition.model)
    if type(related) ~= "table" or type(related.query) ~= "function" then
        return nil, "relation " .. name .. " has an invalid model"
    end
    local resolved = { name = name, type = definition.type, related = related }
    if definition.type == "belongs_to" then
        resolved.foreign_key = definition.foreign_key or Relations.default_foreign_key(related.table)
        resolved.owner_key = definition.owner_key or related.primary_key
    else
        resolved.foreign_key = definition.foreign_key or Relations.default_foreign_key(class.table)
        resolved.local_key = definition.local_key or class.primary_key
    end
    return resolved
end

-- { "posts.comments", { author = fn } } ->
-- tree.posts = { nested = { "comments" } }, tree.author = { constraint = fn, nested = {} }
function Relations.parse(specs)
    local tree, order = {}, {}
    local function node(name)
        if not tree[name] then
            tree[name] = { nested = {} }
            order[#order + 1] = name
        end
        return tree[name]
    end
    local function add(path, constraint)
        if type(path) ~= "string" or path == "" then error("relation name must be a non-empty string", 4) end
        local head, rest = path:match("^([^%.]+)%.(.+)$")
        if head then
            local entry = node(head)
            entry.nested[#entry.nested + 1] = constraint and { [rest] = constraint } or rest
        else
            local entry = node(path)
            entry.constraint = constraint or entry.constraint
        end
    end
    for _, spec in ipairs(specs) do
        if type(spec) == "table" then
            for key, value in pairs(spec) do
                if type(key) == "number" then add(value) else add(key, value) end
            end
        else
            add(spec)
        end
    end
    return tree, order
end

local function key_of(value)
    if value == nil then return nil end
    return tostring(value)
end

local function unique_keys(models, column)
    local seen, keys = {}, {}
    for _, model in ipairs(models) do
        local value = model.attributes[column]
        local key = key_of(value)
        if key and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = value
        end
    end
    return keys
end

-- Loads relation `name` onto every model in `models` with a single query.
function Relations.load(class, models, name, options, adapter)
    options = options or {}
    local relation, err = Relations.definition(class, name)
    if not relation then return nil, err end
    local is_many = relation.type == "has_many"
    local parent_column = relation.type == "belongs_to" and relation.foreign_key or relation.local_key
    local related_column = relation.type == "belongs_to" and relation.owner_key or relation.foreign_key

    local keys = unique_keys(models, parent_column)
    local grouped = {}
    if #keys > 0 then
        local query = relation.related:query(adapter):where_in(related_column, keys)
        if options.constraint then options.constraint(query) end
        if options.nested and #options.nested > 0 then query:with(unpack_values(options.nested)) end
        local rows, query_err, errno, sqlstate, kind = query:get()
        if not rows then return nil, query_err, errno, sqlstate, kind end
        for _, row in ipairs(rows) do
            local key = key_of(row.attributes[related_column])
            if key then
                grouped[key] = grouped[key] or {}
                local bucket = grouped[key]
                bucket[#bucket + 1] = row
            end
        end
    end

    for _, model in ipairs(models) do
        local bucket = grouped[key_of(model.attributes[parent_column])]
        if is_many then
            model.related[name] = bucket or {}
        else
            -- false marks "loaded, but nothing related" so it is not reloaded.
            model.related[name] = bucket and bucket[1] or false
        end
    end
    return true
end

function Relations.eager_load(class, models, specs, adapter)
    if #models == 0 or #specs == 0 then return true end
    local tree, order = Relations.parse(specs)
    for _, name in ipairs(order) do
        local ok, err, errno, sqlstate, kind = Relations.load(class, models, name, tree[name], adapter)
        if not ok then return nil, err, errno, sqlstate, kind end
    end
    return true
end

return Relations
