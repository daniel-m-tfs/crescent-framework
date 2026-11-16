-- Code templates for the `make:*` generators. Placeholders are `{{key}}` and
-- are only ever filled with names that passed `is_valid_name`.
local Templates = {}

local MAX_NAME_LENGTH = 64

-- Letters, digits, "_" and "-", starting with a letter. Names become paths,
-- `require` strings and Lua identifiers, so nothing else is accepted.
function Templates.is_valid_name(name)
    return type(name) == "string"
        and #name <= MAX_NAME_LENGTH
        and name:match("^[%a][%w_%-]*$") ~= nil
end

function Templates.snake(name)
    local value = name:gsub("%-", "_")
    value = value:gsub("(%u)(%u%l)", "%1_%2")
    value = value:gsub("([%l%d])(%u)", "%1_%2")
    value = value:lower():gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
    return value
end

function Templates.pascal(name)
    local parts = {}
    for part in Templates.snake(name):gmatch("[^_]+") do
        parts[#parts + 1] = part:sub(1, 1):upper() .. part:sub(2)
    end
    return table.concat(parts)
end

function Templates.plural(word)
    if word:match("[^aeiou]y$") then return word:sub(1, -2) .. "ies" end
    if word:match("s$") then return word end
    if word:match("x$") or word:match("z$") or word:match("ch$") or word:match("sh$") then
        return word .. "es"
    end
    return word .. "s"
end

-- Variables shared by every template for a resource `name` inside `module`.
function Templates.vars(name, module_name)
    local snake = Templates.snake(name)
    return {
        name = snake,
        Name = Templates.pascal(name),
        module = Templates.snake(module_name or name),
        plural = Templates.plural(snake),
    }
end

function Templates.render(template, vars)
    return (template:gsub("{{([%w_]+)}}", function(key)
        local value = vars[key]
        if value == nil then error("missing template variable: " .. key, 0) end
        return tostring(value)
    end))
end

Templates.action = [[
local {{Name}}Action = {}

function {{Name}}Action.index(ctx)
    return ctx:json(200, { data = {} })
end

function {{Name}}Action.show(ctx)
    return ctx:json(200, { data = { id = ctx.params.id } })
end

return {{Name}}Action
]]

Templates.service = [[
local {{Name}}Service = {}

function {{Name}}Service.example(value)
    return value
end

return {{Name}}Service
]]

Templates.model = [[
local Model = require("crescent.model")

return Model:extend({
    table = "{{plural}}",
    fillable = { "name" },
    hidden = {},
    timestamps = true,
    validates = {
        name = { required = true, string = true, min_length = 1, max_length = 255 },
    },
})
]]

Templates.routes = [[
local action = require("src.{{module}}.actions.{{name}}")

return function(app, prefix)
    app:get(prefix, action.index)
    app:get(prefix .. "/{id}", action.show)
end
]]

Templates.middleware = [[
-- Register with: app:use(require("{{require_path}}"))
return function(ctx, next)
    return next()
end
]]

Templates.test = [[
package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")

local function example()
    tests.assertEquals(1 + 1, 2)
end

assert(tests.runSuite("{{Name}}", { example = example }))
]]

Templates.migration = [[
-- Migration: {{migration}}
return {
    up = function()
        return [=[
CREATE TABLE IF NOT EXISTS `{{table}}` (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
]=]
    end,

    down = function()
        return "DROP TABLE IF EXISTS `{{table}}`"
    end,
}
]]

-- Guesses the table from create_<t>_table / drop_<t>_table / ..._to_<t>.
function Templates.migration_table(name)
    local snake = name:gsub("%-", "_")
    return snake:match("^create_(.+)_table$")
        or snake:match("^drop_(.+)_table$")
        or snake:match("^update_(.+)_table$")
        or snake:match("_to_(.+)$")
        or snake:match("_from_(.+)$")
        or "example"
end

-- CRUD module (make:module) -------------------------------------------------

Templates.module_init = [[
local Module = {}

function Module.register(app)
    local routes = require("src.{{module}}.routes.{{name}}")
    routes(app, "/{{plural}}")
end

return Module
]]

Templates.module_routes = [[
local action = require("src.{{module}}.actions.{{name}}")

return function(app, prefix)
    app:get(prefix, action.index, "{{plural}}.index")
    app:get(prefix .. "/{id}", action.show, "{{plural}}.show")
    app:post(prefix, app:validated(action.schema, action.store), "{{plural}}.store")
    app:put(prefix .. "/{id}", app:validated(action.schema, action.update), "{{plural}}.update")
    app:delete(prefix .. "/{id}", action.destroy, "{{plural}}.destroy")
end
]]

Templates.module_action = [[
local json = require("crescent.json")
local {{Name}}Service = require("src.{{module}}.services.{{name}}")

local {{Name}}Action = {}

{{Name}}Action.schema = {
    name = { required = true, string = true, min_length = 1, max_length = 255 },
}

-- Actions expect a crescent.database adapter on ctx.db (or app.db).
local function with_db(handler)
    return function(ctx)
        local db = ctx.db or (ctx.app and ctx.app.db)
        if not db then
            return ctx:error(503, "database is not configured", nil, "database_unavailable")
        end
        return handler(ctx, db)
    end
end

local function failure(ctx, message, err, identifier)
    if type(err) == "table" then
        return ctx:error(422, "validation failed", err, "validation_failed")
    end
    return ctx:error(500, message, ctx.debug and err or nil, identifier)
end

{{Name}}Action.index = with_db(function(ctx, db)
    local records, err = {{Name}}Service.list(db)
    if not records then return failure(ctx, "unable to list {{plural}}", err, "{{name}}_list_failed") end
    return ctx:json(200, { data = json.array(records) })
end)

{{Name}}Action.show = with_db(function(ctx, db)
    local record, err = {{Name}}Service.find(db, ctx.params.id)
    if err then return failure(ctx, "unable to load {{name}}", err, "{{name}}_load_failed") end
    if not record then return ctx:error(404, "{{name}} not found", nil, "{{name}}_not_found") end
    return ctx:json(200, { data = record })
end)

{{Name}}Action.store = with_db(function(ctx, db)
    local record, err = {{Name}}Service.create(db, ctx.body)
    if not record then return failure(ctx, "unable to create {{name}}", err, "{{name}}_create_failed") end
    return ctx:json(201, { data = record })
end)

{{Name}}Action.update = with_db(function(ctx, db)
    local record, err = {{Name}}Service.update(db, ctx.params.id, ctx.body)
    if err then return failure(ctx, "unable to update {{name}}", err, "{{name}}_update_failed") end
    if not record then return ctx:error(404, "{{name}} not found", nil, "{{name}}_not_found") end
    return ctx:json(200, { data = record })
end)

{{Name}}Action.destroy = with_db(function(ctx, db)
    local deleted, err = {{Name}}Service.delete(db, ctx.params.id)
    if err then return failure(ctx, "unable to delete {{name}}", err, "{{name}}_delete_failed") end
    if not deleted then return ctx:error(404, "{{name}} not found", nil, "{{name}}_not_found") end
    return ctx:no_content()
end)

return {{Name}}Action
]]

Templates.module_service = [[
local QueryBuilder = require("crescent.database.query_builder")
local {{Name}} = require("src.{{module}}.models.{{name}}")

-- Every function takes a crescent.database adapter as `db` and returns
-- `value` or `nil, err` (err is a table of field errors on validation failure).
local {{Name}}Service = {}

local function query()
    return QueryBuilder.new():table({{Name}}.table)
end

local function present(row)
    local result = {}
    for key, value in pairs(row) do result[key] = value end
    for _, key in ipairs({{Name}}.hidden or {}) do result[key] = nil end
    return result
end

function {{Name}}Service.list(db)
    local rows, err = query():order_by({{Name}}.primary_key):fetch(db)
    if not rows then return nil, err end
    local records = {}
    for index, row in ipairs(rows) do records[index] = present(row) end
    return records
end

-- Returns the record, `nil` when it does not exist, or `nil, err`.
function {{Name}}Service.find(db, id)
    local rows, err = query():where({{Name}}.primary_key, id):limit(1):fetch(db)
    if not rows then return nil, err end
    return rows[1] and present(rows[1]) or nil
end

function {{Name}}Service.create(db, attributes)
    local record = {{Name}}:new(attributes)
    local saved, err = record:save(db)
    if not saved then return nil, err end
    return present(record.attributes)
end

function {{Name}}Service.update(db, id, attributes)
    local current, err = {{Name}}Service.find(db, id)
    if not current then return nil, err end
    local record = {{Name}}:new()
    for key, value in pairs(current) do record.attributes[key] = value end
    record:fill(attributes)
    record.exists = true
    local saved, save_error = record:save(db)
    if not saved then return nil, save_error end
    return present(record.attributes)
end

function {{Name}}Service.delete(db, id)
    local current, err = {{Name}}Service.find(db, id)
    if not current then return nil, err end
    local deleted, delete_error = query():where({{Name}}.primary_key, id):delete(db)
    if not deleted then return nil, delete_error end
    return true
end

return {{Name}}Service
]]

Templates.module_test = [[
package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")

local function registers_routes()
    local app = Crescent.new({ environment = "test", debug = true })
    require("src.{{module}}").register(app)
    tests.assertEquals(app:route("{{plural}}.index"), "/{{plural}}")
    tests.assertEquals(app:route("{{plural}}.show"), "/{{plural}}/{id}")
end

assert(tests.runSuite("{{Name}} module", { registers_routes = registers_routes }))
]]

return Templates
