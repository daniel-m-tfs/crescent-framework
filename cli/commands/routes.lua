-- `routes`: loads app.lua (needs the OpenResty runtime, use bin/crescent) and
-- prints every registered route.
local cli_output = require("crescent.utils.cli_output")

local Routes = {}

local METHOD_ORDER = { GET = 1, HEAD = 2, POST = 3, PUT = 4, PATCH = 5, DELETE = 6, OPTIONS = 7 }

function Routes.collect(app)
    local rows = {}
    for method, routes in pairs(app.router.routes) do
        for _, route in ipairs(routes) do
            rows[#rows + 1] = { method = method, path = route.path, name = route.name or "" }
        end
    end
    table.sort(rows, function(left, right)
        if left.path ~= right.path then return left.path < right.path end
        return (METHOD_ORDER[left.method] or 99) < (METHOD_ORDER[right.method] or 99)
    end)
    return rows
end

function Routes.format(rows)
    local widths = { #"METHOD", #"PATH" }
    for _, row in ipairs(rows) do
        widths[1] = math.max(widths[1], #row.method)
        widths[2] = math.max(widths[2], #row.path)
    end
    local line = "%-" .. widths[1] .. "s  %-" .. widths[2] .. "s  %s"
    local lines = { (string.format(line, "METHOD", "PATH", "NAME"):gsub("%s+$", "")) }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = (string.format(line, row.method, row.path, row.name):gsub("%s+$", ""))
    end
    return table.concat(lines, "\n")
end

function Routes.run(module_name)
    local ok, app = pcall(require, module_name or "app")
    if not ok then
        cli_output.print_error("unable to load app.lua: " .. tostring(app))
        if not ngx then cli_output.print_info("run it on OpenResty: ./bin/crescent routes") end
        return false
    end
    if type(app) ~= "table" or type(app.router) ~= "table" then
        cli_output.print_error("app.lua must return the application")
        return false
    end
    local rows = Routes.collect(app)
    print(Routes.format(rows))
    print(string.format("\n%d route(s)", #rows))
    return true
end

return Routes
