-- crescent/utils/cli_output.lua
-- Helpers de output colorido compartilhados por crescent-cli.lua e crescent/database/migrate.lua

local M = {}

M.colors = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    bold = "\27[1m",
    dim = "\27[2m"
}

local colors = M.colors

function M.print_header(text)
    print("\n" .. colors.bold .. colors.blue .. "🌙 " .. text .. colors.reset .. "\n")
end

function M.print_success(text)
    print(colors.green .. "✓ " .. text .. colors.reset)
end

function M.print_error(text)
    print(colors.red .. "✗ " .. text .. colors.reset)
end

function M.print_info(text)
    print(colors.yellow .. "ℹ " .. text .. colors.reset)
end

function M.print_debug(text)
    print(colors.dim .. "  " .. text .. colors.reset)
end

return M
