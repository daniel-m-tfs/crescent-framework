local tests = {}
local json = require('json')

-- ==========================================
-- COMPARAÇÕES BÁSICAS
-- ==========================================

function tests.assertEquals(actual, expected, message)
    if actual ~= expected then
        error(message or string.format("Expected %s but got %s", tostring(expected), tostring(actual)), 2)
    end
end

function tests.assertNotEquals(actual, expected, message)
    if actual == expected then
        error(message or string.format("Expected values to be different, but both are %s", tostring(actual)), 2)
    end
end

function tests.assertTrue(value, message)
    if not value then
        error(message or "Expected true but got false", 2)
    end
end

function tests.assertFalse(value, message)
    if value then
        error(message or "Expected false but got true", 2)
    end
end

-- ==========================================
-- COMPARAÇÕES NUMÉRICAS
-- ==========================================

function tests.assertGreaterThan(actual, expected, message)
    if type(actual) ~= "number" or type(expected) ~= "number" then
        error("assertGreaterThan requires numbers", 2)
    end
    if actual <= expected then
        error(message or string.format("Expected %s to be greater than %s", actual, expected), 2)
    end
end

function tests.assertLessThan(actual, expected, message)
    if type(actual) ~= "number" or type(expected) ~= "number" then
        error("assertLessThan requires numbers", 2)
    end
    if actual >= expected then
        error(message or string.format("Expected %s to be less than %s", actual, expected), 2)
    end
end

function tests.assertGreaterOrEqual(actual, expected, message)
    if type(actual) ~= "number" or type(expected) ~= "number" then
        error("assertGreaterOrEqual requires numbers", 2)
    end
    if actual < expected then
        error(message or string.format("Expected %s to be greater than or equal to %s", actual, expected), 2)
    end
end

function tests.assertLessOrEqual(actual, expected, message)
    if type(actual) ~= "number" or type(expected) ~= "number" then
        error("assertLessOrEqual requires numbers", 2)
    end
    if actual > expected then
        error(message or string.format("Expected %s to be less than or equal to %s", actual, expected), 2)
    end
end

function tests.assertInRange(value, min, max, message)
    if type(value) ~= "number" or type(min) ~= "number" or type(max) ~= "number" then
        error("assertInRange requires numbers", 2)
    end
    if value < min or value > max then
        error(message or string.format("Expected %s to be between %s and %s", value, min, max), 2)
    end
end

-- ==========================================
-- COMPARAÇÕES DE TIPOS
-- ==========================================

function tests.assertType(value, expectedType, message)
    local actualType = type(value)
    if actualType ~= expectedType then
        error(message or string.format("Expected type %s but got %s", expectedType, actualType), 2)
    end
end

function tests.assertNil(value, message)
    if value ~= nil then
        error(message or string.format("Expected nil but got %s", tostring(value)), 2)
    end
end

function tests.assertNotNil(value, message)
    if value == nil then
        error(message or "Expected non-nil value but got nil", 2)
    end
end

function tests.assertIsTable(value, message)
    if type(value) ~= "table" then
        error(message or string.format("Expected table but got %s", type(value)), 2)
    end
end

function tests.assertIsFunction(value, message)
    if type(value) ~= "function" then
        error(message or string.format("Expected function but got %s", type(value)), 2)
    end
end

function tests.assertIsString(value, message)
    if type(value) ~= "string" then
        error(message or string.format("Expected string but got %s", type(value)), 2)
    end
end

function tests.assertIsNumber(value, message)
    if type(value) ~= "number" then
        error(message or string.format("Expected number but got %s", type(value)), 2)
    end
end

function tests.assertIsBoolean(value, message)
    if type(value) ~= "boolean" then
        error(message or string.format("Expected boolean but got %s", type(value)), 2)
    end
end

-- ==========================================
-- COMPARAÇÕES DE STRINGS
-- ==========================================

function tests.assertContains(haystack, needle, message)
    if type(haystack) ~= "string" then
        error("assertContains requires a string as first argument", 2)
    end
    if not string.find(haystack, needle, 1, true) then
        error(message or string.format("Expected '%s' to contain '%s'", haystack, needle), 2)
    end
end

function tests.assertNotContains(haystack, needle, message)
    if type(haystack) ~= "string" then
        error("assertNotContains requires a string as first argument", 2)
    end
    if string.find(haystack, needle, 1, true) then
        error(message or string.format("Expected '%s' to not contain '%s'", haystack, needle), 2)
    end
end

function tests.assertStartsWith(str, prefix, message)
    if type(str) ~= "string" or type(prefix) ~= "string" then
        error("assertStartsWith requires strings", 2)
    end
    if string.sub(str, 1, #prefix) ~= prefix then
        error(message or string.format("Expected '%s' to start with '%s'", str, prefix), 2)
    end
end

function tests.assertEndsWith(str, suffix, message)
    if type(str) ~= "string" or type(suffix) ~= "string" then
        error("assertEndsWith requires strings", 2)
    end
    if string.sub(str, -#suffix) ~= suffix then
        error(message or string.format("Expected '%s' to end with '%s'", str, suffix), 2)
    end
end

function tests.assertMatches(str, pattern, message)
    if type(str) ~= "string" or type(pattern) ~= "string" then
        error("assertMatches requires strings", 2)
    end
    if not string.match(str, pattern) then
        error(message or string.format("Expected '%s' to match pattern '%s'", str, pattern), 2)
    end
end

-- ==========================================
-- COMPARAÇÕES DE TABLES
-- ==========================================

local function deepCompare(t1, t2)
    if type(t1) ~= type(t2) then return false end
    if type(t1) ~= "table" then return t1 == t2 end
    
    for k, v in pairs(t1) do
        if not deepCompare(v, t2[k]) then return false end
    end
    
    for k, v in pairs(t2) do
        if not deepCompare(v, t1[k]) then return false end
    end
    
    return true
end

function tests.assertTableEquals(actual, expected, message)
    if type(actual) ~= "table" or type(expected) ~= "table" then
        error("assertTableEquals requires tables", 2)
    end
    if not deepCompare(actual, expected) then
        error(message or "Tables are not equal", 2)
    end
end

function tests.assertTableContains(tbl, value, message)
    if type(tbl) ~= "table" then
        error("assertTableContains requires a table as first argument", 2)
    end
    for _, v in pairs(tbl) do
        if v == value then
            return
        end
    end
    error(message or string.format("Table does not contain value %s", tostring(value)), 2)
end

function tests.assertEmpty(tbl, message)
    if type(tbl) ~= "table" then
        error("assertEmpty requires a table", 2)
    end
    if next(tbl) ~= nil then
        error(message or "Expected empty table but got non-empty table", 2)
    end
end

function tests.assertNotEmpty(tbl, message)
    if type(tbl) ~= "table" then
        error("assertNotEmpty requires a table", 2)
    end
    if next(tbl) == nil then
        error(message or "Expected non-empty table but got empty table", 2)
    end
end

function tests.assertLength(tbl, expected, message)
    if type(tbl) ~= "table" then
        error("assertLength requires a table", 2)
    end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    if count ~= expected then
        error(message or string.format("Expected table length %d but got %d", expected, count), 2)
    end
end

function tests.assertArrayLength(arr, expected, message)
    if type(arr) ~= "table" then
        error("assertArrayLength requires a table", 2)
    end
    if #arr ~= expected then
        error(message or string.format("Expected array length %d but got %d", expected, #arr), 2)
    end
end

-- ==========================================
-- EXCEPTIONS/ERRORS
-- ==========================================

function tests.assertError(fn, expectedMessage, message)
    if type(fn) ~= "function" then
        error("assertError requires a function", 2)
    end
    
    local success, err = pcall(fn)
    if success then
        error(message or "Expected function to throw an error but it didn't", 2)
    end
    
    if expectedMessage and not string.find(tostring(err), expectedMessage, 1, true) then
        error(message or string.format("Expected error containing '%s' but got '%s'", expectedMessage, tostring(err)), 2)
    end
end

function tests.assertNoError(fn, message)
    if type(fn) ~= "function" then
        error("assertNoError requires a function", 2)
    end
    
    local success, err = pcall(fn)
    if not success then
        error(message or string.format("Expected no error but got: %s", tostring(err)), 2)
    end
end

-- ==========================================
-- HTTP/API TESTING
-- ==========================================

function tests.assertStatusCode(response, expected, message)
    if type(response) ~= "table" or not response.status then
        error("assertStatusCode requires a response object with status field", 2)
    end
    if response.status ~= expected then
        error(message or string.format("Expected status code %d but got %d", expected, response.status), 2)
    end
end

function tests.assertHeader(response, headerName, expectedValue, message)
    if type(response) ~= "table" or not response.headers then
        error("assertHeader requires a response object with headers field", 2)
    end
    
    local actualValue = response.headers[headerName]
    if actualValue ~= expectedValue then
        error(message or string.format("Expected header '%s' to be '%s' but got '%s'", 
            headerName, tostring(expectedValue), tostring(actualValue)), 2)
    end
end

function tests.assertJsonEquals(jsonStr, expected, message)
    if type(jsonStr) ~= "string" then
        error("assertJsonEquals requires a JSON string as first argument", 2)
    end
    
    local success, actual = pcall(json.parse, jsonStr)
    if not success then
        error("Failed to parse JSON string", 2)
    end
    
    if not deepCompare(actual, expected) then
        error(message or "JSON content does not match expected value", 2)
    end
end

function tests.assertJsonContains(jsonStr, key, expectedValue, message)
    if type(jsonStr) ~= "string" then
        error("assertJsonContains requires a JSON string as first argument", 2)
    end
    
    local success, data = pcall(json.parse, jsonStr)
    if not success then
        error("Failed to parse JSON string", 2)
    end
    
    if data[key] ~= expectedValue then
        error(message or string.format("Expected JSON key '%s' to be '%s' but got '%s'", 
            key, tostring(expectedValue), tostring(data[key])), 2)
    end
end

-- ==========================================
-- UTILIDADES
-- ==========================================

function tests.assertSame(actual, expected, message)
    if actual ~= expected then
        error(message or "Expected same reference/identity but got different objects", 2)
    end
end

function tests.assertNotSame(actual, expected, message)
    if actual == expected then
        error(message or "Expected different references/identities but got same object", 2)
    end
end

-- Helper para executar suíte de testes
function tests.run(name, testFunction)
    print(string.format("Running test: %s", name))
    local success, err = pcall(testFunction)
    if success then
        print(string.format("✅ %s passed", name))
        return true
    else
        print(string.format("❌ %s failed: %s", name, err))
        return false
    end
end

function tests.runSuite(suiteName, testSuite)
    print(string.format("\n=== Test Suite: %s ===", suiteName))
    local passed = 0
    local failed = 0
    local total = 0
    
    for name, testFn in pairs(testSuite) do
        if type(testFn) == "function" then
            total = total + 1
            if tests.run(name, testFn) then
                passed = passed + 1
            else
                failed = failed + 1
            end
        end
    end
    
    print(string.format("\n=== Results: %d/%d passed, %d failed ===\n", passed, total, failed))
    return failed == 0
end

return tests