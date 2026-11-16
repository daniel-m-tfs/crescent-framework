#!/usr/bin/env lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local cli_output = require("crescent.utils.cli_output")
local test_command = require("cli.commands.test")

local function show_help()
    cli_output.print_header("Crescent CLI")
    print([[
Usage: lua cli.lua <command>

Commands:
  test [filter]  Run Lua tests in tests/ (on OpenResty LuaJIT)
    test:http  Run HTTP integration tests against OpenResty
  help    Show this help
]])
end

local command = arg[1] or "help"
if command == "test" then
    if not test_command.run(arg[2]) then os.exit(1) end
elseif command == "test:http" then
    if not test_command.run_http() then os.exit(1) end
elseif command == "help" or command == "--help" or command == "-h" then
    show_help()
else
    cli_output.print_error("Unknown command: " .. command)
    show_help()
    os.exit(2)
end