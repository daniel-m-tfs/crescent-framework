package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Response = require("crescent.response")

local function response_tests()
	local writer = { headers = {}, sent = false }
	Response.new(writer):text("hello")
	tests.assertEquals(writer.status, 200, "default response status must be 200")
	tests.assertEquals(writer.headers["Content-Type"], "text/plain; charset=utf-8")
	tests.assertEquals(writer.body, "hello", "response body must be written")

	local html_writer = { headers = {}, sent = false }
	Response.new(html_writer):html("<p>hello</p>")
	tests.assertEquals(html_writer.headers["Content-Type"], "text/html; charset=utf-8")

	local errored = { headers = {}, sent = false }
	Response.new(errored):error(422, "invalid input")
	tests.assertEquals(errored.status, 422, "error status must be preserved")
	tests.assertContains(errored.body, '"code":"http_error"', "error code must be stable")
	tests.assertContains(errored.body, "invalid input", "error message must be serialized")
end

assert(tests.runSuite("Response", { responses = response_tests }))
