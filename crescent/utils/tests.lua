local tests = {}

local function fail(message, level)
    error(message, (level or 1) + 1)
end

local function deep_compare(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end

    for key, value in pairs(left) do
        if not deep_compare(value, right[key]) then return false end
    end
    for key, value in pairs(right) do
        if not deep_compare(value, left[key]) then return false end
    end
    return true
end

function tests.assertEquals(actual, expected, message)
    if actual ~= expected then
        fail(message or string.format("Expected %s but got %s", tostring(expected), tostring(actual)), 2)
    end
end

function tests.assertNotEquals(actual, expected, message)
    if actual == expected then
        fail(message or string.format("Expected values to differ, both were %s", tostring(actual)), 2)
    end
end

function tests.assertTrue(value, message)
    if not value then fail(message or "Expected true but got false", 2) end
end

function tests.assertFalse(value, message)
    if value then fail(message or "Expected false but got true", 2) end
end

function tests.assertNil(value, message)
    if value ~= nil then fail(message or "Expected nil", 2) end
end

function tests.assertNotNil(value, message)
    if value == nil then fail(message or "Expected a non-nil value", 2) end
end

function tests.assertType(value, expected_type, message)
    if type(value) ~= expected_type then
        fail(message or string.format("Expected type %s but got %s", expected_type, type(value)), 2)
    end
end

function tests.assertIsString(value, message)
    tests.assertType(value, "string", message)
end

function tests.assertIsNumber(value, message)
    tests.assertType(value, "number", message)
end

function tests.assertIsTable(value, message)
    tests.assertType(value, "table", message)
end

function tests.assertIsFunction(value, message)
    tests.assertType(value, "function", message)
end

function tests.assertContains(haystack, needle, message)
    tests.assertIsString(haystack, "assertContains requires a string")
    if not haystack:find(needle, 1, true) then
        fail(message or string.format("Expected '%s' to contain '%s'", haystack, needle), 2)
    end
end

function tests.assertNotContains(haystack, needle, message)
    tests.assertIsString(haystack, "assertNotContains requires a string")
    if haystack:find(needle, 1, true) then
        fail(message or string.format("Expected '%s' not to contain '%s'", haystack, needle), 2)
    end
end

function tests.assertMatches(value, pattern, message)
    tests.assertIsString(value, "assertMatches requires a string")
    if not value:match(pattern) then
        fail(message or string.format("Expected '%s' to match '%s'", value, pattern), 2)
    end
end

function tests.assertTableEquals(actual, expected, message)
    if not deep_compare(actual, expected) then
        fail(message or "Tables are not equal", 2)
    end
end

function tests.assertError(fn, expected_message, message)
    tests.assertIsFunction(fn, "assertError requires a function")
    local ok, err = pcall(fn)
    if ok then fail(message or "Expected function to throw an error", 2) end
    if expected_message and not tostring(err):find(expected_message, 1, true) then
        fail(message or string.format("Expected error containing '%s'", expected_message), 2)
    end
end

function tests.assertNoError(fn, message)
    tests.assertIsFunction(fn, "assertNoError requires a function")
    local ok, err = pcall(fn)
    if not ok then fail(message or tostring(err), 2) end
end

local cli_output = require("crescent.utils.cli_output")
local colors = cli_output.colors

-- Error message without the traceback.
local function describe(err)
    local text = tostring(err)
    return (text:gsub("\nstack traceback:.*$", ""))
end

function tests.run(name, test_function)
    local ok, err = pcall(test_function)
    if ok then
        print("    " .. colors.green .. "✓" .. colors.reset .. " " .. name)
        return true
    end
    print("    " .. colors.red .. "✗ " .. name .. colors.reset)
    for line in (describe(err) .. "\n"):gmatch("([^\n]*)\n") do
        print("        " .. colors.red .. line .. colors.reset)
    end
    return false
end

-- The "Result: X/Y passed, Z failed" line is parsed by `crescent test`.
function tests.runSuite(suite_name, suite)
    local names = {}
    for name, test_function in pairs(suite) do
        if type(test_function) == "function" then names[#names + 1] = name end
    end
    table.sort(names)

    print("  " .. colors.bold .. suite_name .. colors.reset)
    local passed = 0
    for _, name in ipairs(names) do
        if tests.run(name, suite[name]) then passed = passed + 1 end
    end

    local failed = #names - passed
    local color = failed == 0 and colors.green or colors.red
    print(string.format("  %sResult: %d/%d passed, %d failed%s", color, passed, #names, failed, colors.reset))
    return failed == 0
end

return tests
