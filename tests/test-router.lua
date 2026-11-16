package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Router = require("crescent.router")

local function route_tests()
	local router = Router.new()
	local literal = function() end
	local parameter = function() end
	local optional = function() end
		local wildcard = function() end

		router:add("GET", "/users/{rest*}", wildcard)
	router:add("GET", "/users/{id}", parameter)
	router:add("GET", "/users/search", literal)
	router:add("GET", "/users/{id?}", optional)

	local action, params = router:match("GET", "/users/search")
	tests.assertEquals(action, literal, "literal route must win over parameter route")
	tests.assertTableEquals(params, {}, "literal route should not have parameters")

	local matched, decoded = router:match("GET", "/users/a%20b")
	tests.assertEquals(matched, parameter, "required parameter route must match")
	tests.assertEquals(decoded.id, "a b", "route parameter must be decoded")

	local optional_match, optional_params = router:match("GET", "/users")
	tests.assertEquals(optional_match, optional, "optional parameter route must match without value")
	tests.assertNil(optional_params.id, "absent optional parameter must be nil")

	local required_match_value, required_value_params = router:match("GET", "/users/42")
	tests.assertEquals(required_match_value, parameter, "required route must win over optional route")
	tests.assertEquals(required_value_params.id, "42", "required parameter value must be decoded")

	local wildcard_match, wildcard_params = router:match("GET", "/users/42/profile/settings")
	tests.assertEquals(wildcard_match, wildcard, "wildcard route must match multiple segments")
	tests.assertEquals(wildcard_params.rest, "42/profile/settings", "wildcard value must preserve segments")

	local encoded_wildcard_match, encoded_wildcard_params = router:match("GET", "/users/a%2Fb/c")
	tests.assertEquals(encoded_wildcard_match, wildcard, "wildcard route must decode values")
	tests.assertEquals(encoded_wildcard_params.rest, "a/b/c", "encoded wildcard slash must be decoded")

	tests.assertNil(router:match("GET", "/users/%ZZ"), "invalid encoding must be rejected")

	local required_only = Router.new()
	required_only:add("GET", "/users/{id}", parameter)
	tests.assertNil(required_only:match("GET", "/users"), "missing required parameter must not match")

	local allowed = router:allowed_methods("/users/search")
	tests.assertEquals(#allowed, 1, "allowed methods must be reported")
	tests.assertEquals(allowed[1], "GET", "GET must be reported as allowed")

	tests.assertError(function()
		Router.new():add("GET", "/files/{path*}/edit", wildcard)
	end, "wildcard parameter must be the final route segment")

	local grouped = Router.new()
	grouped:group("/api", function(router)
		router:add("GET", "/health", literal, "api.health")
	end)
	local grouped_action, _, grouped_path = grouped:match("GET", "/api/health")
	tests.assertEquals(grouped_action, literal, "group prefix must be applied")
	tests.assertEquals(grouped_path, "/api/health", "grouped route path must be complete")
	tests.assertEquals(grouped:find("api.health"), "/api/health", "named route must resolve its path")
	tests.assertError(function()
		grouped:add("GET", "/other", literal, "api.health")
	end, "route name already registered")
end

assert(tests.runSuite("Router", { routes = route_tests }))
