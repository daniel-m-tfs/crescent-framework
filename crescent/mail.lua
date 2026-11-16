-- SMTP mail on lua-resty-mail (non-blocking cosockets, STARTTLS). Usable
-- wherever cosockets are allowed (content phase, ngx.timer, `resty`).
--
--   local Mail = require("crescent.mail")
--   local mailer = Mail.new({ server = "smtp.example.com", port = 587, user = "...", password = "..." })
--   local ok, err = mailer:send({ to = "ada@example.com", subject = "Hi", text = "Hello" })
--
-- Missing config fields fall back to SMTP_SERVER, SMTP_PORT, SMTP_USER,
-- SMTP_PASSWORD, SMTP_FROM and SMTP_FROM_NAME (declare them with `env` in
-- nginx.conf).
local Env = require("crescent.env")

local Mail = {}
Mail.__index = Mail

local EMAIL_PATTERN = "^[%w.!#$%%&'*+/=?^_`{|}~-]+@[%w-]+%.[%w.-]*%w$"

local function default_factory(options)
    return require("resty.mail").new(options)
end

function Mail.is_valid_email(email)
    return type(email) == "string"
        and #email <= 254
        and email:match(EMAIL_PATTERN) ~= nil
        and not email:find("..", 1, true)
end

local function has_line_break(value)
    return type(value) == "string" and value:find("[%z\r\n]") ~= nil
end

-- RFC 2047 encoded-word for non-ASCII header text.
local function encode_header_text(value)
    if not value:find("[\128-\255]") then return value end
    local encode = ngx and ngx.encode_base64
    if not encode then return value end
    return "=?UTF-8?B?" .. encode(value) .. "?="
end

local function format_address(email, name)
    if name == nil or name == "" then return email end
    local encoded = encode_header_text(name)
    if encoded ~= name then return encoded .. " <" .. email .. ">" end
    return '"' .. name:gsub('[\\"]', "\\%0") .. '" <' .. email .. ">"
end

-- Accepts "a@x.com", { "a@x.com", ... } or { { email = "a@x.com", name = "A" }, ... }.
-- Returns formatted header values and bare addresses, or nil, err.
local function parse_recipients(value, field)
    if value == nil then return {}, {} end
    local list = type(value) == "table" and (value.email and { value } or value) or { value }
    local formatted, addresses = {}, {}
    for _, recipient in ipairs(list) do
        local email, name = recipient, nil
        if type(recipient) == "table" then email, name = recipient.email, recipient.name end
        if has_line_break(email) or has_line_break(name) then
            return nil, "invalid characters in " .. field
        end
        if name ~= nil and type(name) ~= "string" then return nil, "invalid name in " .. field end
        if not Mail.is_valid_email(email) then return nil, "invalid email address in " .. field .. ": " .. tostring(email) end
        formatted[#formatted + 1] = format_address(email, name)
        addresses[#addresses + 1] = email
    end
    return formatted, addresses
end

local function pick(config, key, env_name, default)
    if config[key] ~= nil then return config[key] end
    local value = Env.get(env_name)
    if value ~= nil and value ~= "" then return value end
    return default
end

-- config: server, port, user, password, from, from_name, ssl (implicit TLS,
-- default when port is 465), starttls (default true), ssl_verify (default
-- true), timeout (seconds, default 10), domain (EHLO name), auth_type
-- ("plain" or "login"), views_root / view (for send_template), factory
-- (returns a resty.mail-compatible mailer; for tests).
function Mail.new(config)
    config = config or {}
    local port = tonumber(pick(config, "port", "SMTP_PORT", 587))
    local user = pick(config, "user", "SMTP_USER")
    local ssl = config.ssl
    if ssl == nil then ssl = port == 465 end
    return setmetatable({
        smtp_server = pick(config, "server", "SMTP_SERVER", "127.0.0.1"),
        smtp_port = port,
        smtp_user = user,
        smtp_password = pick(config, "password", "SMTP_PASSWORD"),
        from_email = pick(config, "from", "SMTP_FROM", user),
        from_name = pick(config, "from_name", "SMTP_FROM_NAME", "Crescent App"),
        ssl = ssl,
        starttls = not ssl and config.starttls ~= false,
        ssl_verify = config.ssl_verify ~= false,
        timeout = config.timeout or 10,
        domain = config.domain,
        auth_type = config.auth_type,
        views_root = config.views_root or "views",
        view = config.view,
        factory = config.factory or default_factory,
    }, Mail)
end

function Mail:_mailer_options()
    local timeout_ms = math.floor(self.timeout * 1000)
    local options = {
        host = self.smtp_server,
        port = self.smtp_port,
        ssl = self.ssl,
        starttls = self.starttls,
        ssl_verify = self.ssl_verify,
        domain = self.domain,
        timeout_connect = timeout_ms,
        timeout_send = timeout_ms,
        timeout_read = timeout_ms,
    }
    if self.smtp_user and self.smtp_user ~= "" then
        options.username = self.smtp_user
        options.password = self.smtp_password or ""
        options.auth_type = self.auth_type or "plain"
    end
    return options
end

-- options: to, cc, bcc, subject, text, html, from, from_name, reply_to.
-- Returns { success, message, recipients } or nil, err.
function Mail:send(options)
    options = options or {}
    if options.to == nil then return nil, "Recipient (to) is required" end
    if type(options.subject) ~= "string" or options.subject == "" then return nil, "Subject is required" end
    if options.html == nil and options.text == nil then return nil, "Email body (html or text) is required" end
    if has_line_break(options.subject) then return nil, "Subject must not contain line breaks" end

    local to, to_addresses = parse_recipients(options.to, "to")
    if not to then return nil, to_addresses end
    if #to == 0 then return nil, "At least one valid recipient is required" end
    local cc, cc_addresses = parse_recipients(options.cc, "cc")
    if not cc then return nil, cc_addresses end
    local bcc, bcc_addresses = parse_recipients(options.bcc, "bcc")
    if not bcc then return nil, bcc_addresses end

    local from_email = options.from or self.from_email
    local from_name = options.from_name or self.from_name
    if has_line_break(from_name) then return nil, "invalid characters in from" end
    if not Mail.is_valid_email(from_email) then return nil, "Sender (from) is not a valid email address" end
    local reply_to
    if options.reply_to ~= nil then
        local formatted, err = parse_recipients(options.reply_to, "reply_to")
        if not formatted then return nil, err end
        reply_to = table.concat(formatted, ", ")
    end

    local mailer, mailer_error = self.factory(self:_mailer_options())
    if not mailer then return nil, "Failed to configure mailer: " .. tostring(mailer_error) end

    local message = {
        from = format_address(from_email, from_name),
        to = to,
        cc = #cc > 0 and cc or nil,
        bcc = #bcc_addresses > 0 and bcc_addresses or nil,
        reply_to = reply_to,
        subject = encode_header_text(options.subject),
        text = options.text,
        html = options.html,
    }
    local called, ok, err = pcall(mailer.send, mailer, message)
    if not called then ok, err = false, ok end
    if not ok then return nil, "Failed to send email: " .. tostring(err) end

    return {
        success = true,
        message = "Email sent successfully",
        recipients = #to_addresses + #cc_addresses + #bcc_addresses,
    }
end

function Mail:send_text(to, subject, text)
    return self:send({ to = to, subject = subject, text = text })
end

function Mail:send_html(to, subject, html, text)
    return self:send({ to = to, subject = subject, html = html, text = text })
end

local function html_to_text(html)
    local text = html:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[Pp]>", "\n\n"):gsub("<[^>]+>", "")
    text = text:gsub("&nbsp;", " "):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
        :gsub("&#39;", "'"):gsub("&amp;", "&")
    text = text:gsub("[ \t]+", " "):gsub(" *\n *", "\n"):gsub("\n\n\n+", "\n\n")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Renders `template` (a crescent.view name such as "emails/welcome.etlua",
-- relative to views_root) and sends it as HTML with a plain-text version.
function Mail:send_template(to, subject, template, data)
    if type(template) == "string" and not template:match("%.etlua$") then template = template .. ".etlua" end
    local view = self.view or require("crescent.view").new(self.views_root)
    local html, err = view:render(template, data or {})
    if not html then return nil, "Failed to render template: " .. tostring(err) end
    return self:send({ to = to, subject = subject, html = html, text = html_to_text(html) })
end

-- Checks that the SMTP server accepts TCP connections.
function Mail:verify()
    local socket = ngx and ngx.socket and ngx.socket.tcp and ngx.socket.tcp()
    if not socket then return false, "cosockets are not available in this context" end
    socket:settimeout(math.floor(self.timeout * 1000))
    local ok, err = socket:connect(self.smtp_server, self.smtp_port)
    if not ok then return false, "Cannot connect to SMTP server: " .. tostring(err) end
    socket:close()
    return true, "SMTP connection successful"
end

-- Module-level API: Mail.new/create plus shortcuts on a default instance
-- configured from the environment.
local M = { new = Mail.new, create = Mail.new, is_valid_email = Mail.is_valid_email, Mailer = Mail }
local default_instance

local function default()
    default_instance = default_instance or Mail.new()
    return default_instance
end

for _, name in ipairs({ "send", "send_text", "send_html", "send_template", "verify" }) do
    M[name] = function(...) return Mail[name](default(), ...) end
end

return M
