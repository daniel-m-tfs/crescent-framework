-- Email Library for Crescent Framework
-- Provides an easy-to-use interface for sending emails via SMTP
-- Supports: HTML/plain text, attachments, templates, multiple recipients

local smtp = require("socket.smtp")
local ltn12 = require("ltn12")
local mime = require("mime")
local env = require("crescent.utils.env")

local Mail = {}
Mail.__index = Mail

-- Create a new Mail client instance
function Mail.new(config)
    local self = setmetatable({}, Mail)
    
    -- Load from config or environment variables
    self.smtp_server = config and config.server or env.get("SMTP_SERVER") or "smtp.gmail.com"
    self.smtp_port = config and config.port or tonumber(env.get("SMTP_PORT")) or 587
    self.smtp_user = config and config.user or env.get("SMTP_USER")
    self.smtp_password = config and config.password or env.get("SMTP_PASSWORD")
    self.from_email = config and config.from or env.get("SMTP_FROM") or self.smtp_user
    self.from_name = config and config.from_name or env.get("SMTP_FROM_NAME") or "Crescent App"
    
    return self
end

-- Validate email address
local function is_valid_email(email)
    if not email then return false end
    return email:match("^[%w%._%+-]+@[%w%._%+-]+%.%w+$") ~= nil
end

-- Format email address with name
local function format_address(email, name)
    if name and name ~= "" then
        return string.format('"%s" <%s>', name, email)
    end
    return email
end

-- Parse recipients (can be string, table of strings, or table of {email, name})
local function parse_recipients(recipients)
    if not recipients then return {} end
    
    if type(recipients) == "string" then
        return { recipients }
    end
    
    if type(recipients) == "table" then
        local parsed = {}
        for _, recipient in ipairs(recipients) do
            if type(recipient) == "string" then
                table.insert(parsed, recipient)
            elseif type(recipient) == "table" and recipient.email then
                table.insert(parsed, recipient.email)
            end
        end
        return parsed
    end
    
    return {}
end

-- Format recipients for headers (with names)
local function format_recipients(recipients)
    if not recipients then return "" end
    
    if type(recipients) == "string" then
        return recipients
    end
    
    if type(recipients) == "table" then
        local formatted = {}
        for _, recipient in ipairs(recipients) do
            if type(recipient) == "string" then
                table.insert(formatted, recipient)
            elseif type(recipient) == "table" and recipient.email then
                table.insert(formatted, format_address(recipient.email, recipient.name))
            end
        end
        return table.concat(formatted, ", ")
    end
    
    return ""
end

-- Build multipart message with HTML and plain text
local function build_multipart_message(html, text)
    local boundary = "----=_Part_" .. os.time() .. math.random(10000, 99999)
    
    local parts = {}
    
    -- Plain text part
    if text then
        table.insert(parts, "--" .. boundary)
        table.insert(parts, "Content-Type: text/plain; charset=utf-8")
        table.insert(parts, "Content-Transfer-Encoding: 8bit")
        table.insert(parts, "")
        table.insert(parts, text)
        table.insert(parts, "")
    end
    
    -- HTML part
    if html then
        table.insert(parts, "--" .. boundary)
        table.insert(parts, "Content-Type: text/html; charset=utf-8")
        table.insert(parts, "Content-Transfer-Encoding: 8bit")
        table.insert(parts, "")
        table.insert(parts, html)
        table.insert(parts, "")
    end
    
    table.insert(parts, "--" .. boundary .. "--")
    
    return table.concat(parts, "\r\n"), boundary
end

-- Send email
function Mail:send(options)
    -- Validate required fields
    if not options.to then
        return nil, "Recipient (to) is required"
    end
    
    if not options.subject then
        return nil, "Subject is required"
    end
    
    if not options.html and not options.text then
        return nil, "Email body (html or text) is required"
    end
    
    -- Validate SMTP configuration
    if not self.smtp_user or not self.smtp_password then
        return nil, "SMTP credentials not configured. Set SMTP_USER and SMTP_PASSWORD in .env"
    end
    
    -- Parse recipients
    local to_addresses = parse_recipients(options.to)
    local cc_addresses = parse_recipients(options.cc)
    local bcc_addresses = parse_recipients(options.bcc)
    
    if #to_addresses == 0 then
        return nil, "At least one valid recipient is required"
    end
    
    -- Build recipient list for SMTP
    local all_recipients = {}
    for _, addr in ipairs(to_addresses) do table.insert(all_recipients, addr) end
    for _, addr in ipairs(cc_addresses) do table.insert(all_recipients, addr) end
    for _, addr in ipairs(bcc_addresses) do table.insert(all_recipients, addr) end
    
    -- Build message headers
    local headers = {
        from = format_address(self.from_email, self.from_name),
        to = format_recipients(options.to),
        subject = options.subject,
        ["date"] = os.date("!%a, %d %b %Y %H:%M:%S +0000"),
        ["message-id"] = string.format("<%s.%s@%s>", os.time(), math.random(10000, 99999), self.smtp_server),
    }
    
    -- Add CC and BCC if present
    if options.cc then
        headers.cc = format_recipients(options.cc)
    end
    
    -- Add reply-to if present
    if options.reply_to then
        headers["reply-to"] = options.reply_to
    end
    
    -- Build message body
    local body
    local content_type
    
    if options.html and options.text then
        -- Multipart message
        local multipart_body, boundary = build_multipart_message(options.html, options.text)
        body = multipart_body
        content_type = "multipart/alternative; boundary=" .. boundary
    elseif options.html then
        -- HTML only
        body = options.html
        content_type = "text/html; charset=utf-8"
    else
        -- Plain text only
        body = options.text
        content_type = "text/plain; charset=utf-8"
    end
    
    headers["content-type"] = content_type
    
    -- Build message
    local message = {
        headers = headers,
        body = body
    }
    
    -- Send email
    local ok, err = smtp.send{
        from = self.from_email,
        rcpt = all_recipients,
        source = smtp.message(message),
        server = self.smtp_server,
        port = self.smtp_port,
        user = self.smtp_user,
        password = self.smtp_password,
    }
    
    if not ok then
        return nil, "Failed to send email: " .. tostring(err)
    end
    
    return {
        success = true,
        message = "Email sent successfully",
        recipients = #all_recipients
    }
end

-- Send simple text email
function Mail:send_text(to, subject, text)
    return self:send({
        to = to,
        subject = subject,
        text = text
    })
end

-- Send HTML email
function Mail:send_html(to, subject, html, text)
    return self:send({
        to = to,
        subject = subject,
        html = html,
        text = text
    })
end

-- Send email using template
function Mail:send_template(to, subject, template_path, data)
    -- Try to load and render template
    local etlua = require("crescent.utils.etlua")
    
    local file = io.open(template_path, "r")
    if not file then
        return nil, "Template file not found: " .. template_path
    end
    
    local template_content = file:read("*all")
    file:close()
    
    -- Render template
    local success, html = pcall(function()
        return etlua.render(template_content, data or {})
    end)
    
    if not success then
        return nil, "Failed to render template: " .. tostring(html)
    end
    
    -- Generate plain text version (basic HTML stripping)
    local text = html:gsub("<[^>]+>", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    
    return self:send({
        to = to,
        subject = subject,
        html = html,
        text = text
    })
end

-- Verify SMTP connection
function Mail:verify()
    if not self.smtp_user or not self.smtp_password then
        return false, "SMTP credentials not configured"
    end
    
    -- Try to send a test connection (without actually sending email)
    local socket = require("socket")
    local client = socket.tcp()
    client:settimeout(10)
    
    local ok, err = client:connect(self.smtp_server, self.smtp_port)
    if not ok then
        return false, "Cannot connect to SMTP server: " .. tostring(err)
    end
    
    client:close()
    return true, "SMTP connection successful"
end

-- Create default instance
local default_instance = Mail.new()

-- Export module with default instance methods
local exports = {
    -- Create custom instance
    create = function(config)
        return Mail.new(config)
    end,
    
    -- Default instance methods
    send = function(options)
        return default_instance:send(options)
    end,
    
    send_text = function(to, subject, text)
        return default_instance:send_text(to, subject, text)
    end,
    
    send_html = function(to, subject, html, text)
        return default_instance:send_html(to, subject, html, text)
    end,
    
    send_template = function(to, subject, template_path, data)
        return default_instance:send_template(to, subject, template_path, data)
    end,
    
    verify = function()
        return default_instance:verify()
    end
}

return exports
