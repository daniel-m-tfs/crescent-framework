package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local View = require("crescent.view")

local function view_tests()
    local view = View.new("tests/fixtures/views")
    view:helper("uppercase", function(value) return value:upper() end)
    local rendered, render_error = view:render("hello.etlua", {
        name = "Ada <script>",
        trusted = "<strong>safe</strong>",
    })
    tests.assertTrue(rendered ~= nil, tostring(render_error))
    tests.assertContains(rendered, "Ada &lt;script&gt;")
    tests.assertContains(rendered, "<strong>safe</strong>")
    local helper_rendered = view:render("helper.etlua", { name = "Ada" })
    tests.assertContains(helper_rendered, "ADA")
    tests.assertNotNil(view:reload("hello.etlua"))
    view:clear("hello.etlua")
    tests.assertNotNil(view:render("hello.etlua", { name = "Reloaded", trusted = "ok" }))

    local cached = view:render("hello.etlua", { name = "Grace", trusted = "ok" })
    tests.assertContains(cached, "Grace")
    local invalid, invalid_error = view:render("../secret.etlua", {})
    tests.assertNil(invalid)
    tests.assertEquals(invalid_error, "invalid template name")

    local partial = view:partial("partial.etlua", { value = "<tag>" })
    tests.assertContains(partial, "&lt;tag&gt;")
    local layout = view:render_layout("layout.etlua", partial, {})
    tests.assertContains(layout, partial)
end

assert(tests.runSuite("Views", { escaping_and_cache = view_tests }))
