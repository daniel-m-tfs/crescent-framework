-- Security response headers with conservative defaults.
--
--   security_headers.create({
--       frame_options = "DENY",                      -- or "SAMEORIGIN", false
--       referrer_policy = "strict-origin-when-cross-origin",
--       content_type_options = true,                 -- X-Content-Type-Options: nosniff
--       hsts = false,                                -- true or { max_age, include_subdomains, preload }
--       csp = nil,                                   -- Content-Security-Policy string
--       permissions_policy = nil,
--       cross_origin_opener_policy = nil,            -- e.g. "same-origin"
--       headers = { ["X-Custom"] = "value", ["Referrer-Policy"] = false },
--   })
--
-- HSTS is opt-in: only enable it when the site is served exclusively over
-- HTTPS, because browsers cache it for `max_age` seconds.
local Response = require("crescent.response")

local SecurityHeaders = {}

local function hsts_value(option)
    if not option then return nil end
    if option == true then option = {} end
    assert(type(option) == "table", "hsts must be a boolean or a table")
    local max_age = option.max_age or 31536000
    assert(type(max_age) == "number" and max_age >= 0, "hsts.max_age must be a non-negative number")
    local value = "max-age=" .. math.floor(max_age)
    if option.include_subdomains ~= false then value = value .. "; includeSubDomains" end
    if option.preload then value = value .. "; preload" end
    return value
end

local function default(value, fallback)
    if value == nil then return fallback end
    return value or nil
end

function SecurityHeaders.build(options)
    options = options or {}
    local frame_options = default(options.frame_options, "DENY")
    if frame_options then
        frame_options = frame_options:upper()
        assert(frame_options == "DENY" or frame_options == "SAMEORIGIN", "frame_options must be DENY, SAMEORIGIN or false")
    end
    local headers = {
        ["X-Content-Type-Options"] = options.content_type_options ~= false and "nosniff" or nil,
        ["X-Frame-Options"] = frame_options,
        ["Referrer-Policy"] = default(options.referrer_policy, "strict-origin-when-cross-origin"),
        ["Strict-Transport-Security"] = hsts_value(options.hsts),
        ["Content-Security-Policy"] = options.csp or nil,
        ["Permissions-Policy"] = options.permissions_policy or nil,
        ["Cross-Origin-Opener-Policy"] = options.cross_origin_opener_policy or nil,
    }
    for name, value in pairs(options.headers or {}) do
        headers[name] = value or nil
    end
    for name, value in pairs(headers) do
        assert(Response.is_safe_header_value(value), "invalid security header value for " .. name)
    end
    return headers
end

-- Headers are set before `next`, so they are present on error responses too.
function SecurityHeaders.create(options)
    local headers = SecurityHeaders.build(options)
    return function(ctx, next)
        ctx.res:headers(headers)
        return next()
    end
end

return SecurityHeaders
