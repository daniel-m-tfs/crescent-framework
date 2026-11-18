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

Templates.controller = [[
-- Controllers receive `ctx`, call services and answer with ctx:json,
-- ctx:text, ctx:view or ctx:error.
local {{Name}}Controller = {}

function {{Name}}Controller.index(ctx)
    return ctx:json(200, { data = {} })
end

function {{Name}}Controller.show(ctx)
    return ctx:json(200, { data = { id = ctx.params.id } })
end

return {{Name}}Controller
]]

Templates.service = [[
-- Business logic for {{name}}; keep it free of ctx so it is easy to test.
local {{Name}}Service = {}

function {{Name}}Service.example(value)
    return value
end

return {{Name}}Service
]]

Templates.job = [[
-- Background job. Push it from a controller or service:
--   ctx.queue:push("src.{{module}}.jobs.{{name}}", { id = 1 })
--   ctx.queue:push("src.{{module}}.jobs.{{name}}", { id = 1 }, { delay = 60 })
-- A raised error (or `return false, err`) retries it after `backoff`
-- seconds; failed() runs after the last attempt. Jobs may run more than
-- once (crash, timeout): keep handle() idempotent.
local {{Name}}Job = {
    queue = "default",
    attempts = 3,
    backoff = { 10, 60, 300 },
    timeout = 60,
}

-- payload: the JSON-decoded table given to push(); job: id, attempts,
-- db, cache, config, dispatch(name, payload, options), log(level, message).
function {{Name}}Job.handle(payload, job)
    job.log("info", "{{name}} running", { attempt = job.attempts })
end

function {{Name}}Job.failed(payload, err, job)
    job.log("error", "{{name}} gave up: " .. tostring(err))
end

return {{Name}}Job
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
local controller = require("src.{{module}}.controllers.{{name}}")

return function(app, prefix)
    app:get(prefix, controller.index, "{{plural}}.index")
    app:get(prefix .. "/{id}", controller.show, "{{plural}}.show")
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

-- `create_<table>[_table]` gets a CREATE TABLE; every other name gets an
-- ALTER TABLE skeleton for the table guessed by migration_table().
Templates.migration = [[
-- Migration: {{migration}}
-- up/down return a SQL string, a list of statements, or { sql = ..., bindings = { ... } }.
-- MySQL DDL commits implicitly: keep one schema change per migration when possible.
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

Templates.migration_alter = [[
-- Migration: {{migration}}
-- up/down return a SQL string, a list of statements, or { sql = ..., bindings = { ... } }.
-- MySQL DDL commits implicitly: keep one schema change per migration when possible.
return {
    up = function()
        return "ALTER TABLE `{{table}}` ADD COLUMN `example` VARCHAR(255) NULL"
    end,

    down = function()
        return "ALTER TABLE `{{table}}` DROP COLUMN `example`"
    end,
}
]]

-- Guesses the table from create_<t>_table / drop_<t>_table / ..._to_<t>.
function Templates.migration_table(name)
    local snake = name:gsub("%-", "_")
    return snake:match("^create_(.+)_table$")
        or snake:match("^create_(.+)$")
        or snake:match("^drop_(.+)_table$")
        or snake:match("^update_(.+)_table$")
        or snake:match("^alter_(.+)_table$")
        or snake:match("_to_(.+)$")
        or snake:match("_from_(.+)$")
        or snake:match("_in_(.+)$")
        or "example"
end

-- Renders the migration file for `name` (without the timestamp prefix).
function Templates.migration_for(name)
    local snake = name:gsub("%-", "_")
    local template = snake:match("^create_.+") and Templates.migration or Templates.migration_alter
    return Templates.render(template, { migration = name, table = Templates.migration_table(name) })
end

-- CRUD module (make:module) -------------------------------------------------

Templates.module_init = [[
local Module = {}

function Module.register(app)
    require("src.{{module}}.routes.{{name}}")(app, "/{{plural}}")
end

return Module
]]

Templates.module_routes = [[
local controller = require("src.{{module}}.controllers.{{name}}")

-- Route names ({{plural}}.index, ...) work with app:route(name) and `crescent routes`.
return function(app, prefix)
    app:get(prefix, controller.index, "{{plural}}.index")
    app:get(prefix .. "/{id}", controller.show, "{{plural}}.show")
    app:post(prefix, app:validated(controller.schema, controller.store), "{{plural}}.store")
    app:put(prefix .. "/{id}", app:validated(controller.schema, controller.update), "{{plural}}.update")
    app:delete(prefix .. "/{id}", controller.destroy, "{{plural}}.destroy")
end
]]

Templates.module_controller = [[
local json = require("crescent.json")
local {{Name}}Service = require("src.{{module}}.services.{{name}}")

local {{Name}}Controller = {}

{{Name}}Controller.schema = {
    name = { required = true, string = true, min_length = 1, max_length = 255 },
}

-- Handlers use the database configured at boot (ctx.db, from config.database).
local function with_db(handler)
    return function(ctx)
        if not ctx.db then
            return ctx:error(503, "database is not configured", nil, "database_unavailable")
        end
        return handler(ctx, ctx.db)
    end
end

-- Validation errors arrive as a table of field errors; anything else is a
-- database failure (details only in debug).
local function failure(ctx, message, err, identifier)
    if type(err) == "table" then
        return ctx:error(422, "validation failed", err, "validation_failed")
    end
    return ctx:error(500, message, ctx.debug and err or nil, identifier)
end

-- GET /{{plural}}?page=1&per_page=15
{{Name}}Controller.index = with_db(function(ctx, db)
    local page, err = {{Name}}Service.page(db, ctx.query.page, ctx.query.per_page)
    if not page then return failure(ctx, "unable to list {{plural}}", err, "{{name}}_list_failed") end
    return ctx:json(200, { data = json.array(page.data), meta = page.meta })
end)

{{Name}}Controller.show = with_db(function(ctx, db)
    local record, err = {{Name}}Service.find(db, ctx.params.id)
    if err then return failure(ctx, "unable to load {{name}}", err, "{{name}}_load_failed") end
    if not record then return ctx:error(404, "{{name}} not found", nil, "{{name}}_not_found") end
    return ctx:json(200, { data = record })
end)

{{Name}}Controller.store = with_db(function(ctx, db)
    local record, err = {{Name}}Service.create(db, ctx.body)
    if not record then return failure(ctx, "unable to create {{name}}", err, "{{name}}_create_failed") end
    return ctx:json(201, { data = record })
end)

{{Name}}Controller.update = with_db(function(ctx, db)
    local record, err = {{Name}}Service.update(db, ctx.params.id, ctx.body)
    if err then return failure(ctx, "unable to update {{name}}", err, "{{name}}_update_failed") end
    if not record then return ctx:error(404, "{{name}} not found", nil, "{{name}}_not_found") end
    return ctx:json(200, { data = record })
end)

{{Name}}Controller.destroy = with_db(function(ctx, db)
    local deleted, err = {{Name}}Service.delete(db, ctx.params.id)
    if err then return failure(ctx, "unable to delete {{name}}", err, "{{name}}_delete_failed") end
    if not deleted then return ctx:error(404, "{{name}} not found", nil, "{{name}}_not_found") end
    return ctx:no_content()
end)

return {{Name}}Controller
]]

Templates.module_service = [[
local {{Name}} = require("src.{{module}}.models.{{name}}")

-- Business logic for {{plural}}. Every function takes the database adapter
-- (`db`, or a transaction) and returns `value` or `nil, err`; `err` is a
-- table of field errors when validation fails. Records are returned as plain
-- tables (`to_table()` drops the model's hidden fields).
local {{Name}}Service = {}

local function present(record)
    return record and record:to_table() or nil
end

function {{Name}}Service.page(db, page, per_page)
    local result, err = {{Name}}:page(page, per_page, nil, db)
    if not result then return nil, err end
    local data = {}
    for index, record in ipairs(result.data) do data[index] = present(record) end
    return { data = data, meta = result.meta }
end

-- Returns the record, `nil` when it does not exist, or `nil, err`.
function {{Name}}Service.find(db, id)
    local record, err = {{Name}}:find(id, db)
    if not record then return nil, err end
    return present(record)
end

function {{Name}}Service.create(db, attributes)
    local record, err = {{Name}}:create(attributes, db)
    if not record then return nil, err end
    return present(record)
end

function {{Name}}Service.update(db, id, attributes)
    local record, err = {{Name}}:find(id, db)
    if not record then return nil, err end
    local saved, save_error = record:update(attributes, db)
    if not saved then return nil, save_error end
    return present(record)
end

-- Returns true, `nil` when it does not exist, or `nil, err`.
function {{Name}}Service.delete(db, id)
    local record, err = {{Name}}:find(id, db)
    if not record then return nil, err end
    local deleted, delete_error = record:delete(db)
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
