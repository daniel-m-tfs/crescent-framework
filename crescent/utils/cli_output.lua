-- Colored terminal output shared by the CLI, the test runner and test suites.
-- Colors are on when stdout is a terminal (or CRESCENT_COLOR=1, which the test
-- runner sets for the files it runs) and off with NO_COLOR or CRESCENT_COLOR=0.
local output = {}

local CODES = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    cyan = "\27[36m",
    bold = "\27[1m",
    dim = "\27[2m",
}

local function detect()
    local forced = os.getenv("CRESCENT_COLOR")
    if forced == "1" then return true end
    if forced == "0" then return false end
    local no_color = os.getenv("NO_COLOR")
    if no_color and no_color ~= "" then return false end
    local term = os.getenv("TERM")
    if term == "dumb" then return false end
    local result = os.execute("test -t 1")
    return result == true or result == 0
end

-- Detected on first use; set `output.enabled` to force it.
output.enabled = nil

function output.is_enabled()
    if output.enabled == nil then output.enabled = detect() end
    return output.enabled
end

-- `colors.<name>` is "" when colors are off, so callers can concatenate freely.
output.colors = setmetatable({}, {
    __index = function(_, name)
        if not output.is_enabled() then return "" end
        return CODES[name] or ""
    end,
})

local colors = output.colors

function output.paint(color, text)
    return colors[color] .. text .. colors.reset
end

function output.rule(char, width)
    return string.rep(char or "─", width or 60)
end

function output.print_header(text)
    print("\n" .. colors.bold .. colors.blue .. "🌙 " .. text .. colors.reset .. "\n")
end

function output.print_success(text)
    print(colors.green .. "✓ " .. text .. colors.reset)
end

function output.print_error(text)
    print(colors.red .. "✗ " .. text .. colors.reset)
end

function output.print_warning(text)
    print(colors.yellow .. "⚠ " .. text .. colors.reset)
end

function output.print_info(text)
    print(colors.cyan .. "ℹ " .. text .. colors.reset)
end

function output.print_debug(text)
    print(colors.dim .. "  " .. text .. colors.reset)
end

-- Indented code the user is expected to copy (e.g. a line for app.lua).
function output.print_code(text)
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        print("    " .. colors.yellow .. line .. colors.reset)
    end
end

return output
