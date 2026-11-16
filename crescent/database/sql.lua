-- Shared SQL helpers: identifier allowlisting, the NULL sentinel and safe
-- `?` placeholder binding for drivers that only speak the text protocol.
local Sql = {}

-- ngx.null is what lua-resty-mysql uses for SQL NULL; outside OpenResty a
-- private sentinel plays the same role.
Sql.NULL = (ngx and ngx.null) or setmetatable({}, { __tostring = function() return "NULL" end })

function Sql.is_null(value)
    return value == nil or value == Sql.NULL
end

local function check_part(part, original)
    if not part:match("^[%a_][%w_]*$") then
        error("invalid SQL identifier: " .. tostring(original), 0)
    end
    return "`" .. part .. "`"
end

-- `users` -> `users`, `users.id` -> `users`.`id`. Anything else is rejected.
function Sql.identifier(value)
    if type(value) ~= "string" or value == "" then
        error("SQL identifier must be a non-empty string", 0)
    end
    local parts = {}
    for part in (value .. "."):gmatch("([^%.]*)%.") do
        parts[#parts + 1] = check_part(part, value)
    end
    return table.concat(parts, ".")
end

-- Select-list entries additionally accept `*`, `table.*` and `column AS alias`.
function Sql.select_identifier(value)
    if value == "*" then return "*" end
    if type(value) ~= "string" then error("SQL identifier must be a non-empty string", 0) end
    local column, alias = value:match("^%s*(.-)%s+[aA][sS]%s+(.-)%s*$")
    if column then return Sql.select_identifier(column) .. " AS " .. check_part(alias, value) end
    local owner = value:match("^(.-)%.%*$")
    if owner then return Sql.identifier(owner) .. ".*" end
    return Sql.identifier(value)
end

-- Same escaping rules as ngx.quote_sql_str (MySQL backslash escapes).
local ESCAPES = {
    ["\0"] = "\\0", ["\b"] = "\\b", ["\n"] = "\\n", ["\r"] = "\\r",
    ["\t"] = "\\t", ["\26"] = "\\Z", ["\\"] = "\\\\", ["'"] = "\\'", ['"'] = '\\"',
}

local function fallback_quote(value)
    return "'" .. value:gsub("[%z\b\n\r\t\26\\'\"]", ESCAPES) .. "'"
end

local function quote_string(value)
    if ngx and ngx.quote_sql_str then return ngx.quote_sql_str(value) end
    return fallback_quote(value)
end

Sql.quote_string = quote_string

-- Returns the SQL literal for a bound value, or nil and an error.
function Sql.literal(value)
    local value_type = type(value)
    if value == nil or value == Sql.NULL then return "NULL" end
    if value_type == "boolean" then return value and "1" or "0" end
    if value_type == "string" then return quote_string(value) end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, "cannot bind NaN or infinite numbers"
        end
        if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            return string.format("%.0f", value)
        end
        return string.format("%.17g", value)
    end
    if value_type == "cdata" then
        local text = tostring(value):match("^(%-?%d+)U?LL$")
        if text then return text end
    end
    return nil, "cannot bind value of type " .. value_type
end

-- Number of bound values. `n` (as set by table.pack) wins, otherwise the
-- highest integer key, so nil holes are still counted.
local function binding_count(bindings)
    if bindings.n then return bindings.n end
    local count = 0
    for key in pairs(bindings) do
        if type(key) == "number" and key > count and key == math.floor(key) then count = key end
    end
    return count
end

-- Splits `sql` into literal chunks around real `?` placeholders. Question
-- marks inside quoted strings, backtick identifiers and comments are text.
local function split_placeholders(sql)
    local chunks, start, index, length = {}, 1, 1, #sql
    while index <= length do
        local char = sql:sub(index, index)
        if char == "'" or char == '"' or char == "`" then
            index = index + 1
            while index <= length do
                local current = sql:sub(index, index)
                if current == "\\" and char ~= "`" then
                    index = index + 1
                elseif current == char then
                    if sql:sub(index + 1, index + 1) == char then
                        index = index + 1
                    else
                        break
                    end
                end
                index = index + 1
            end
        elseif char == "-" and sql:sub(index, index + 2):match("^%-%-[%s]") or char == "#" then
            index = (sql:find("\n", index, true) or length)
        elseif char == "/" and sql:sub(index + 1, index + 1) == "*" then
            local finish = sql:find("*/", index + 2, true)
            index = finish and finish + 1 or length
        elseif char == "?" then
            chunks[#chunks + 1] = sql:sub(start, index - 1)
            start = index + 1
        end
        index = index + 1
    end
    chunks[#chunks + 1] = sql:sub(start)
    return chunks
end

-- Replaces each `?` with the escaped literal of the matching binding.
-- Returns the final SQL, or nil and an error.
function Sql.bind(sql, bindings)
    if type(sql) ~= "string" then return nil, "SQL must be a string" end
    bindings = bindings or {}
    if type(bindings) ~= "table" then return nil, "SQL bindings must be a table" end
    local chunks = split_placeholders(sql)
    local expected, received = #chunks - 1, binding_count(bindings)
    if expected ~= received then
        return nil, string.format("binding count mismatch: expected %d, got %d", expected, received)
    end
    if expected == 0 then return sql end
    local parts = { chunks[1] }
    for index = 1, expected do
        local literal, err = Sql.literal(bindings[index])
        if not literal then return nil, "binding #" .. index .. ": " .. err end
        parts[#parts + 1] = literal
        parts[#parts + 1] = chunks[index + 1]
    end
    return table.concat(parts)
end

return Sql
