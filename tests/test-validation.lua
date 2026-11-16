package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Validation = require("crescent.validation")

local function validation_tests()
    local validator = Validation.new({
        name = { required = true, string = true, min_length = 3, max_length = 8 },
        email = { required = true, email = true },
        age = { required = true, number = true, range = { 18, 120 } },
        slug = { format = "^[a-z%-]+$" },
        nickname = { custom = function(value) return value ~= "blocked", "nickname is blocked" end },
    })

    local valid, valid_errors = validator:validate({
        name = "Crescent",
        email = "dev@example.com",
        age = 30,
        slug = "lua-framework",
        nickname = "dev",
    })
    tests.assertTrue(valid)
    tests.assertTableEquals(valid_errors, {})

    local invalid, errors = validator:validate({
        name = "a",
        email = "invalid",
        age = 12,
        slug = "Invalid_42",
        nickname = "blocked",
    })
    tests.assertFalse(invalid)
    tests.assertEquals(errors.name[1].code, "min_length")
    tests.assertEquals(errors.email[1].code, "email")
    tests.assertEquals(errors.age[1].code, "range")
    tests.assertEquals(errors.slug[1].code, "format")
    tests.assertEquals(errors.nickname[1].message, "nickname is blocked")

    local missing, missing_errors = validator:validate({})
    tests.assertFalse(missing)
    tests.assertEquals(missing_errors.name[1].code, "required")
    tests.assertEquals(missing_errors.email[1].code, "required")

    local wrong_type, wrong_type_errors = validator:validate("not a table")
    tests.assertFalse(wrong_type)
    tests.assertEquals(wrong_type_errors._[1].code, "type")
    tests.assertEquals(wrong_type_errors._[1].message, "input must be a table")

    local static_valid = Validation.validate({ name = "Lua" }, { name = { required = true } })
    tests.assertTrue(static_valid)
end

assert(tests.runSuite("Validation", { rules = validation_tests }))