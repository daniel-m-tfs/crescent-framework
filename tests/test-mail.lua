package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Mail = require("crescent.mail")

local function fake(send_result, send_error)
    local state = {}
    local function factory(options)
        state.options = options
        return {
            send = function(_, message)
                state.message = message
                if send_result == "throw" then error("sslhandshake error: boom") end
                return send_result ~= false, send_error
            end,
        }
    end
    return factory, state
end

local function mailer(factory, extra)
    local config = {
        server = "smtp.example.com", port = 587, user = "app@example.com", password = "secret",
        from = "app@example.com", from_name = "App", factory = factory,
    }
    for key, value in pairs(extra or {}) do config[key] = value end
    return Mail.new(config)
end

local function sends_message()
    local factory, state = fake()
    local result, err = mailer(factory):send({
        to = { "ada@example.com", { email = "grace@example.com", name = "Grace \"G\" Hopper" } },
        cc = "cc@example.com",
        bcc = { "hidden@example.com" },
        reply_to = "support@example.com",
        subject = "Hello",
        text = "Plain",
        html = "<p>Rich</p>",
    })
    tests.assertNil(err)
    tests.assertTrue(result.success)
    tests.assertEquals(result.recipients, 4)
    tests.assertEquals(state.options.host, "smtp.example.com")
    tests.assertEquals(state.options.port, 587)
    tests.assertTrue(state.options.starttls)
    tests.assertFalse(state.options.ssl)
    tests.assertTrue(state.options.ssl_verify)
    tests.assertEquals(state.options.username, "app@example.com")
    tests.assertEquals(state.options.auth_type, "plain")
    tests.assertEquals(state.message.from, '"App" <app@example.com>')
    tests.assertEquals(state.message.to[1], "ada@example.com")
    tests.assertEquals(state.message.to[2], '"Grace \\"G\\" Hopper" <grace@example.com>')
    tests.assertEquals(state.message.cc[1], "cc@example.com")
    tests.assertEquals(state.message.bcc[1], "hidden@example.com")
    tests.assertEquals(state.message.reply_to, "support@example.com")
    tests.assertEquals(state.message.text, "Plain")
end

local function implicit_tls_and_no_auth()
    local factory, state = fake()
    local mail = Mail.new({ server = "smtp.example.com", port = 465, from = "a@example.com", factory = factory })
    tests.assertNotNil(mail:send_text("b@example.com", "Hi", "x"))
    tests.assertTrue(state.options.ssl)
    tests.assertFalse(state.options.starttls)
    tests.assertNil(state.options.username)
    tests.assertNil(state.options.auth_type)
end

local function rejects_header_injection()
    local factory, state = fake()
    local mail = mailer(factory)
    local cases = {
        { to = "a@example.com", subject = "Hi\r\nBcc: victim@example.com", text = "x" },
        { to = "a@example.com\r\nBcc: v@example.com", subject = "Hi", text = "x" },
        { to = { { email = "a@example.com", name = "A\nB" } }, subject = "Hi", text = "x" },
        { to = "a@example.com", subject = "Hi", text = "x", reply_to = "r@example.com\nX: y" },
        { to = "a@example.com", subject = "Hi", text = "x", from_name = "Evil\r\n" },
        { to = "not-an-email", subject = "Hi", text = "x" },
        { to = "a@example.com", cc = "bad@", subject = "Hi", text = "x" },
        { to = "a@example.com", subject = "Hi", text = "x", from = "nobody" },
        { to = {}, subject = "Hi", text = "x" },
        { subject = "Hi", text = "x" },
        { to = "a@example.com", text = "x" },
        { to = "a@example.com", subject = "Hi" },
    }
    for index, case in ipairs(cases) do
        local result, err = mail:send(case)
        tests.assertNil(result, "case " .. index .. " must be rejected")
        tests.assertIsString(err)
    end
    tests.assertNil(state.message, "nothing may reach the mailer")
end

local function reports_failures()
    local factory = fake(false, "connect failure: refused")
    local result, err = mailer(factory):send_html("a@example.com", "Hi", "<b>x</b>")
    tests.assertNil(result)
    tests.assertContains(err, "connect failure: refused")
    result, err = mailer((fake("throw"))):send_text("a@example.com", "Hi", "x")
    tests.assertNil(result)
    tests.assertContains(err, "sslhandshake error")
end

local function encodes_non_ascii_headers()
    local factory, state = fake()
    mailer(factory, { from_name = "Ação" }):send_text("a@example.com", "Olá", "x")
    tests.assertEquals(state.message.subject, "=?UTF-8?B?" .. ngx.encode_base64("Olá") .. "?=")
    tests.assertContains(state.message.from, "=?UTF-8?B?")
end

local function sends_template()
    local factory, state = fake()
    local mail = mailer(factory, { views_root = "tests/fixtures/views" })
    local result, err = mail:send_template("a@example.com", "Welcome", "hello", { name = "Ada <x>", trusted = "<b>Hi</b> &amp; bye" })
    tests.assertNil(err)
    tests.assertTrue(result.success)
    tests.assertContains(state.message.html, "Ada &lt;x&gt;")
    tests.assertContains(state.message.text, "Hi & bye")
    tests.assertNotContains(state.message.text, "<b>")
    result, err = mail:send_template("a@example.com", "Welcome", "../secret", {})
    tests.assertNil(result)
    tests.assertContains(err, "invalid template name")
end

-- The data handed to the mailer must build a valid message with the real
-- lua-resty-mail serializer.
local function compatible_with_resty_mail()
    local factory, state = fake()
    mailer(factory):send({ to = "a@example.com", bcc = "b@example.com", subject = "Hi", text = "Body" })
    local message = require("resty.mail.message").new({ options = { domain = "example.com" } }, state.message)
    local raw = message:get_body_string()
    tests.assertContains(raw, "Subject: Hi\r\n")
    tests.assertContains(raw, "To: a@example.com\r\n")
    tests.assertNotContains(raw, "b@example.com")
    local recipients = message:get_recipient_addresses()
    tests.assertEquals(#recipients, 2)
    tests.assertEquals(message:get_from_address(), "app@example.com")
end

local function email_validation()
    tests.assertTrue(Mail.is_valid_email("first.last+tag@mail.example.co.uk"))
    tests.assertFalse(Mail.is_valid_email("a@b"))
    tests.assertFalse(Mail.is_valid_email("a..b@example.com"))
    tests.assertFalse(Mail.is_valid_email("a b@example.com"))
    tests.assertFalse(Mail.is_valid_email("<a@example.com>"))
    tests.assertFalse(Mail.is_valid_email(nil))
end

assert(tests.runSuite("Mail", {
    sends_message = sends_message,
    implicit_tls_and_no_auth = implicit_tls_and_no_auth,
    rejects_header_injection = rejects_header_injection,
    reports_failures = reports_failures,
    encodes_non_ascii_headers = encodes_non_ascii_headers,
    sends_template = sends_template,
    compatible_with_resty_mail = compatible_with_resty_mail,
    email_validation = email_validation,
}))
