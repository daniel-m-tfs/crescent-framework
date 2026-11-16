local cli_output = require("crescent.utils.cli_output")

local TestCommand = {}

local function is_test_file(path)
    local name = path:match("([^/]+)$") or path
    return name:match("^test[^/]*%.lua$") ~= nil
        or name:match("^tests[^/]*%.lua$") ~= nil
end

local function find_test_files()
    local files = {}
    local handle = io.popen("find tests test -type f -name '*.lua' 2>/dev/null")
    if not handle then return files end
    for path in handle:lines() do
        if is_test_file(path) then files[#files + 1] = path end
    end
    handle:close()
    table.sort(files)
    return files
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run_file(path)
    local command = "lua " .. shell_quote(path) .. " 2>&1; printf '\n__CRESCENT_EXIT__:%s\n' $?"
    local handle = io.popen(command)
    if not handle then return false, "unable to start lua" end
    local output = handle:read("*a") or ""
    handle:close()
    local exit_code = tonumber(output:match("__CRESCENT_EXIT__:(%d+)%s*$")) or 1
    output = output:gsub("\n__CRESCENT_EXIT__:%d+%s*$", "")
    return exit_code == 0, output
end

function TestCommand.run()
    cli_output.print_header("Crescent tests")
    local files = find_test_files()
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