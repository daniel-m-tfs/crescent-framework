local cli_output = require("crescent.utils.cli_output")
local colors = cli_output.colors

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
    -- Child output is piped, so colors are forwarded explicitly.
    local color = cli_output.is_enabled() and "1" or "0"
    local command = "CRESCENT_COLOR=" .. color .. " " .. shell_quote(resty_bin())
        .. " -I lua_modules/share/lua/5.1 --shdict 'crescent_limits 1m' --shdict 'crescent_jwt 1m' --shdict 'crescent_sessions 1m' "
        .. shell_quote(path) .. " 2>&1; printf '\n__CRESCENT_EXIT__:%s\n' $?"
    local handle = io.popen(command)
    if not handle then return false, "unable to start resty" end
    local output = handle:read("*a") or ""
    handle:close()
    local exit_code = tonumber(output:match("__CRESCENT_EXIT__:(%d+)%s*$")) or 1
    output = output:gsub("\n__CRESCENT_EXIT__:%d+%s*$", "")
    return exit_code == 0, output
end

-- Sums the "Result: X/Y passed" lines printed by tests.runSuite.
local function count_tests(output)
    local passed, total = 0, 0
    for suite_passed, suite_total in output:gmatch("Result: (%d+)/(%d+) passed") do
        passed = passed + tonumber(suite_passed)
        total = total + tonumber(suite_total)
    end
    return passed, total
end

local function plural(count, word)
    return string.format("%d %s%s", count, word, count == 1 and "" or "s")
end

function TestCommand.run(filter)
    cli_output.print_header("Crescent tests")
    local files = find_test_files(filter)
    if #files == 0 then
        if filter then
            cli_output.print_error("No test files match '" .. filter .. "'")
        else
            cli_output.print_error("No test files found in tests/ or test/")
            cli_output.print_info("Test files are named test-*.lua (e.g. tests/test-users.lua); create one with make:test <name>")
        end
        return false
    end
    cli_output.print_info(string.format("Found %s%s", plural(#files, "test file"),
        filter and (" matching '" .. filter .. "'") or ""))

    local started = os.time()
    local passed_files, passed_tests, total_tests = 0, 0, 0
    local failures = {}
    for _, path in ipairs(files) do
        print("\n" .. colors.bold .. "📄 " .. path .. colors.reset)
        print(colors.dim .. cli_output.rule() .. colors.reset)
        local ok, output = run_file(path)
        output = output:gsub("%s+$", "")
        if output ~= "" then print(output) end
        local file_passed, file_total = count_tests(output)
        passed_tests, total_tests = passed_tests + file_passed, total_tests + file_total
        if ok then
            passed_files = passed_files + 1
        else
            failures[#failures + 1] = path
            if file_passed == file_total then
                cli_output.print_error("exited with an error (see the output above)")
            end
        end
    end

    print("\n" .. colors.bold .. cli_output.rule("═") .. colors.reset)
    cli_output.print_header("Test summary")
    print(string.format("  Files:  %d run, %s, %s", #files,
        cli_output.paint("green", passed_files .. " passed"),
        cli_output.paint(#failures > 0 and "red" or "dim", #failures .. " failed")))
    print(string.format("  Tests:  %d run, %s, %s", total_tests,
        cli_output.paint("green", passed_tests .. " passed"),
        cli_output.paint(total_tests > passed_tests and "red" or "dim", (total_tests - passed_tests) .. " failed")))
    print(string.format("  Time:   %ds", os.difftime(os.time(), started)))
    print("")

    if #failures == 0 then
        print(colors.green .. colors.bold .. string.format("✅ All tests passed! (%d/%d files)", passed_files, #files) .. colors.reset)
    else
        print(colors.red .. colors.bold .. string.format("❌ Some tests failed (%d passed, %d failed)", passed_files, #failures) .. colors.reset)
        for _, path in ipairs(failures) do print("   " .. cli_output.paint("red", "✗ " .. path)) end
    end
    print("")
    return #failures == 0
end

function TestCommand.run_http()
    cli_output.print_header("Crescent HTTP integration")
    local script = io.open("tests/test-http.sh", "r")
    if not script then
        cli_output.print_error("tests/test-http.sh not found")
        return false
    end
    script:close()
    local result = os.execute("bash tests/test-http.sh")
    local success = result == true or result == 0
    if success then
        cli_output.print_success("HTTP integration passed")
    else
        cli_output.print_error("HTTP integration failed")
    end
    return success
end

return TestCommand
