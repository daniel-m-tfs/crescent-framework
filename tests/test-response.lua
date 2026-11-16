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

local function append_and_get_header()
	local writer = { headers = {} }
	local res = Response.new(writer)
	res:append_header("Set-Cookie", "a=1")
	tests.assertEquals(writer.headers["Set-Cookie"], "a=1", "a single value stays a string")
	res:append_header("set-cookie", "b=2")
	res:append_header("SET-COOKIE", { "c=3", "d=4" })
	tests.assertTableEquals(writer.headers["Set-Cookie"], { "a=1", "b=2", "c=3", "d=4" })
	tests.assertTableEquals(res:get_header("set-cookie"), { "a=1", "b=2", "c=3", "d=4" })
	tests.assertNil(res:get_header("X-Missing"))

	res:header("Content-Type", "text/plain")
	res:header("content-type", "application/json")
	tests.assertNil(writer.headers["Content-Type"], "header() replaces differently-cased names")
	tests.assertEquals(res:get_header("CONTENT-TYPE"), "application/json")

	tests.assertError(function() res:append_header("X-Bad", "a\r\nInjected: 1") end, "invalid response header value")
	tests.assertError(function() res:append_header("X-Bad", { "ok", "b\nc" }) end, "invalid response header value")
	tests.assertError(function() res:append_header("Bad Name", "x") end, "invalid response header name")
	tests.assertError(function() res:append_header("X-Nil", nil) end, "requires a value")
end

local function before_flush_hooks()
	local flushed_headers
	local writer = { headers = {}, flush = function(w) flushed_headers = w.headers["X-Hook"] end }
	local res = Response.new(writer)
	local calls = 0
	res:before_flush(function(response)
		calls = calls + 1
		tests.assertEquals(response.writer.status, 201, "hooks see the final status")
		response:append_header("X-Hook", "ran")
	end)
	res:status(201):text("x")
	res:text("again")
	tests.assertEquals(calls, 1, "hooks run once")
	tests.assertEquals(flushed_headers, "ran", "hooks run before flush")
	tests.assertEquals(writer.body, "x")

	local failing = { headers = {} }
	local failing_res = Response.new(failing)
	failing_res:before_flush(function() error("hook failed") end)
	tests.assertError(function() failing_res:text("x") end, "hook failed")
	tests.assertFalse(failing_res:is_sent(), "a failing hook aborts the send")
	failing_res:status(500):text("error page")
	tests.assertEquals(failing.body, "error page")
end

assert(tests.runSuite("Response", {
	responses = response_tests,
	append_and_get_header = append_and_get_header,
	before_flush_hooks = before_flush_hooks,
}))
