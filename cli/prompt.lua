-- Interactive questions for the CLI. `Prompt.input` reads one line (nil at
-- end of input) and is replaced in tests; with piped stdin every question
-- takes its answer from the next line, and an empty line takes the default.
local cli_output = require("crescent.utils.cli_output")
local colors = cli_output.colors

local Prompt = {}

function Prompt.input()
    return io.read("*l")
end

local function stdin_is_tty()
    local result = os.execute("test -t 0")
    return result == true or result == 0
end

local function trim(value)
    return value and (value:gsub("^%s+", ""):gsub("%s+$", "")) or nil
end

local function question(text, hint)
    io.write(colors.cyan .. "? " .. colors.reset .. colors.bold .. text .. colors.reset)
    if hint and hint ~= "" then io.write(" " .. colors.dim .. "(" .. hint .. ")" .. colors.reset) end
    io.write(" ")
    io.flush()
end

-- Returns the answer, or `default` for an empty answer or end of input.
function Prompt.ask(text, default)
    question(text, default)
    local answer = trim(Prompt.input())
    if answer == nil or answer == "" then return default end
    return answer
end

function Prompt.confirm(text, default)
    question(text, default and "Y/n" or "y/N")
    while true do
        local answer = trim(Prompt.input())
        if answer == nil or answer == "" then return default end
        answer = answer:lower()
        if answer == "y" or answer == "yes" or answer == "s" or answer == "sim" then return true end
        if answer == "n" or answer == "no" or answer == "nao" or answer == "não" then return false end
        question("Answer y or n:")
    end
end

-- Like ask, without echoing what is typed (when stdin is a terminal).
function Prompt.secret(text, hint)
    question(text, hint)
    local hide = Prompt.input == Prompt.default_input and stdin_is_tty()
    if hide then os.execute("stty -echo 2>/dev/null") end
    local answer = Prompt.input()
    if hide then
        os.execute("stty echo 2>/dev/null")
        io.write("\n")
    end
    return trim(answer)
end

Prompt.default_input = Prompt.input

return Prompt
