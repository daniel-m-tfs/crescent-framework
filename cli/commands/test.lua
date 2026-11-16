local cli_output = require("crescent.utils.cli_output")

local TestCommand = {}

local function is_test_file(path)
    local name = path:match("([^/]+)$") or path
    return name:match("^test[^/]*%.lua$") ~= nil
        or name:match("^tests[^/]*%.lua$") ~= nil
end

local function find_test_files(filter)
    local files = {}
    local handle = io.popen("find tests test -type f -name '*.lua' 2>/dev/null")
    if not handle then return files end
    for path in handle:lines() do
        if is_test_file(path) and (not filter or path:find(filter, 1, true)) then
            files[#files + 1] = path
        end
    end
    handle:close()
    table.sort(files)
    return files
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

-- Tests run on OpenResty's LuaJIT through the `resty` CLI, the same runtime
-- that serves requests. Override the binary with RESTY_BIN.
local function resty_bin()
    local configured = os.getenv("RESTY_BIN")
    if configured and configured ~= "" then return configured end
    for _, candidate in ipairs({ "/opt/homebrew/opt/openresty/bin/resty", "/usr/local/openresty/bin/resty", "/opt/openresty/bin/resty" }) do
        local file = io.open(candidate, "r")
        if file then file:close() return candidate end
    end
    return "resty"
end

local function run_file(path)
    local command = shell_quote(resty_bin())
        .. " -I lua_modules/share/lua/5.1 --shdict 'crescent_limits 1m' --shdict 'crescent_jwt 1m' --shdict 'crescent_sessions 1m' "
        .. shell_quote(path) .. " 2>&1; printf '\n__CRESCENT_EXIT__:%s\n' $?"
    local handle = io.popen(command)
    if not handle then return false, "unable to start lua" end
    local output = handle:read("*a") or ""
    handle:close()
    local exit_code = tonumber(output:match("__CRESCENT_EXIT__:(%d+)%s*$")) or 1
    output = output:gsub("\n__CRESCENT_EXIT__:%d+%s*$", "")
    return exit_code == 0, output
end

function TestCommand.run(filter)
    cli_output.print_header("Crescent tests")
    local files = find_test_files(filter)
    if #files == 0 then
        cli_output.print_error("No test files found in tests/ or test/")
        return false
    end

    local passed = 0
    for _, path in ipairs(files) do
        print("\nRunning " .. path)
        local ok, output = run_file(path)
        io.write(output)
        if ok then passed = passed + 1 end
    end

    local failed = #files - passed
    print(string.format("\nResult: %d/%d files passed, %d failed", passed, #files, failed))
    return failed == 0
end

function TestCommand.run_http()
    cli_output.print_header("Crescent HTTP integration")
    local result = os.execute("bash tests/test-http.sh")
    local success = result == true or result == 0
    if not success then cli_output.print_error("HTTP integration failed") end
    return success
end

return TestCommand