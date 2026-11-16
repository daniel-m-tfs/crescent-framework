local etlua = require("etlua")

local View = {}
View.__index = View

local function valid_name(name)
    return type(name) == "string"
        and name:match("^[%w_%-/]+%.etlua$") ~= nil
        and not name:find("..", 1, true)
end

function View.new(root, options)
    options = options or {}
    return setmetatable({
        root = root or "views",
        cache = {},
        cache_enabled = options.cache ~= false,
        helpers = options.helpers or {},
    }, View)
end

function View:_load(name)
    if not valid_name(name) then return nil, "invalid template name" end
    if self.cache_enabled and self.cache[name] then return self.cache[name] end

    local file, open_error = io.open(self.root .. "/" .. name, "r")
    if not file then return nil, open_error end
    local source = file:read("*a")
    file:close()

    local template, compile_error = etlua.compile(source)
    if not template then return nil, compile_error end
    if self.cache_enabled then self.cache[name] = template end
    return template
end

function View:render(name, data)
    local template, load_error = self:_load(name)
    if not template then return nil, load_error end
    local context = {}
    for key, value in pairs(self.helpers) do context[key] = value end
    for key, value in pairs(data or {}) do context[key] = value end
    local ok, result = pcall(template, context)
    if not ok then return nil, result end
    return result
end

function View:helper(name, fn)
    if type(name) ~= "string" or not name:match("^[%a_][%w_]*$") then
        error("invalid view helper name", 2)
    end
    if type(fn) ~= "function" then error("view helper must be a function", 2) end
    self.helpers[name] = fn
    return self
end

function View:partial(name, data)
    return self:render(name, data)
end

function View:render_layout(layout, content, data)
    data = data or {}
    data.content = content
    return self:render(layout, data)
end

function View:clear(name)
    if name then self.cache[name] = nil else self.cache = {} end
end

function View:reload(name)
    self:clear(name)
    return self:_load(name)
end

return View
