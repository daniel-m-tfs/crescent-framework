local output = {}

output.colors = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m",
    yellow = "\27[33m",
    blue = "\27[34m",
    bold = "\27[1m",
}

local colors = output.colors

function output.print_header(text)
    print(colors.bold .. colors.blue .. text .. colors.reset)
end

function output.print_error(text)
    print(colors.red .. "ERROR " .. text .. colors.reset)
end

function output.print_info(text)
    print(colors.yellow .. "INFO " .. text .. colors.reset)
end

return output