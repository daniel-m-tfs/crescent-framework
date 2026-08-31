-- crescent/utils/json_fallback.lua
-- JSON encode/decode mínimo, pure-Lua, usado quando require("json") não está
-- disponível no ambiente Luvit

local M = {}

local bit
do
  local ok, b = pcall(require, "bit")
  if ok then bit = b end
  if not bit then
    ok, b = pcall(require, "bit32")
    if ok then bit = b end
  end
end
assert(bit, "bit/bit32 is required (LuaJIT/Luvit should provide it)")

local band, rshift = bit.band, bit.rshift

local function is_array(t)
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    if k <= 0 or k % 1 ~= 0 then return false end
    if k > n then n = k end
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true, n
end

local escapes = {
  ['"']  = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}

local function escape_str(s)
  return s:gsub('[%z\1-\31\\"]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end)
end

function M.encode(v)
  local tv = type(v)
  if v == nil then return "null" end
  if tv == "boolean" then return v and "true" or "false" end
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      error("invalid number in json")
    end
    return tostring(v)
  end
  if tv == "string" then
    return '"' .. escape_str(v) .. '"'
  end
  if tv == "table" then
    local arr, n = is_array(v)
    if arr then
      local out = {}
      for i = 1, n do out[i] = M.encode(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    else
      local out = {}
      for k, val in pairs(v) do
        if type(k) ~= "string" then
          error("json object keys must be strings")
        end
        out[#out + 1] = M.encode(k) .. ":" .. M.encode(val)
      end
      return "{" .. table.concat(out, ",") .. "}"
    end
  end
  error("unsupported type in json: " .. tv)
end

-- JSON decoder (minimal, enough for JWT claims)
local function decode_error(msg, s, i)
  error(msg .. " at position " .. tostring(i) .. " near '" .. s:sub(i, i + 20) .. "'")
end

local function skip_ws(s, i)
  while true do
    local c = s:byte(i)
    if not c then return i end
    if c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D then
      i = i + 1
    else
      return i
    end
  end
end

local function parse_literal(s, i, lit, val)
  if s:sub(i, i + #lit - 1) == lit then
    return val, i + #lit
  end
  decode_error("invalid literal", s, i)
end

local function codepoint_to_utf8(cp)
  if cp <= 0x7F then
    return string.char(cp)
  elseif cp <= 0x7FF then
    return string.char(0xC0 + rshift(cp, 6), 0x80 + band(cp, 0x3F))
  elseif cp <= 0xFFFF then
    return string.char(
      0xE0 + rshift(cp, 12),
      0x80 + band(rshift(cp, 6), 0x3F),
      0x80 + band(cp, 0x3F)
    )
  else
    return string.char(
      0xF0 + rshift(cp, 18),
      0x80 + band(rshift(cp, 12), 0x3F),
      0x80 + band(rshift(cp, 6), 0x3F),
      0x80 + band(cp, 0x3F)
    )
  end
end

local function parse_string(s, i)
  -- expects opening quote at i
  i = i + 1
  local out = {}
  local o = 1
  while true do
    local c = s:byte(i)
    if not c then decode_error("unterminated string", s, i) end
    if c == 0x22 then -- "
      return table.concat(out), i + 1
    elseif c == 0x5C then -- backslash
      local esc = s:byte(i + 1)
      if not esc then decode_error("bad escape", s, i) end
      if esc == 0x22 then out[o] = '"'; i = i + 2
      elseif esc == 0x5C then out[o] = "\\"; i = i + 2
      elseif esc == 0x2F then out[o] = "/"; i = i + 2
      elseif esc == 0x62 then out[o] = "\b"; i = i + 2
      elseif esc == 0x66 then out[o] = "\f"; i = i + 2
      elseif esc == 0x6E then out[o] = "\n"; i = i + 2
      elseif esc == 0x72 then out[o] = "\r"; i = i + 2
      elseif esc == 0x74 then out[o] = "\t"; i = i + 2
      elseif esc == 0x75 then
        local hex = s:sub(i + 2, i + 5)
        if #hex < 4 or not hex:match("^[0-9a-fA-F]+$") then
          decode_error("invalid unicode escape", s, i)
        end
        local cp = tonumber(hex, 16)
        i = i + 6
        -- handle surrogate pair
        if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
          local hex2 = s:sub(i + 2, i + 5)
          if #hex2 == 4 and hex2:match("^[0-9a-fA-F]+$") then
            local cp2 = tonumber(hex2, 16)
            if cp2 >= 0xDC00 and cp2 <= 0xDFFF then
              cp = 0x10000 + (cp - 0xD800) * 0x400 + (cp2 - 0xDC00)
              i = i + 6
            end
          end
        end
        out[o] = codepoint_to_utf8(cp)
      else
        decode_error("invalid escape char", s, i)
      end
      o = o + 1
    else
      out[o] = string.char(c)
      o = o + 1
      i = i + 1
    end
  end
end

local function parse_number(s, i)
  local start = i
  local c = s:sub(i, i)
  if c == "-" then i = i + 1 end
  if s:sub(i, i) == "0" then
    i = i + 1
  else
    if not s:sub(i, i):match("%d") then decode_error("invalid number", s, i) end
    while s:sub(i, i):match("%d") do i = i + 1 end
  end
  if s:sub(i, i) == "." then
    i = i + 1
    if not s:sub(i, i):match("%d") then decode_error("invalid number fraction", s, i) end
    while s:sub(i, i):match("%d") do i = i + 1 end
  end
  local e = s:sub(i, i)
  if e == "e" or e == "E" then
    i = i + 1
    local sign = s:sub(i, i)
    if sign == "+" or sign == "-" then i = i + 1 end
    if not s:sub(i, i):match("%d") then decode_error("invalid exponent", s, i) end
    while s:sub(i, i):match("%d") do i = i + 1 end
  end
  local num = tonumber(s:sub(start, i - 1))
  if num == nil then decode_error("invalid number", s, start) end
  return num, i
end

local parse_value

local function parse_array(s, i)
  i = i + 1 -- skip [
  local arr = {}
  i = skip_ws(s, i)
  if s:sub(i, i) == "]" then return arr, i + 1 end
  local idx = 1
  while true do
    local v; v, i = parse_value(s, i)
    arr[idx] = v; idx = idx + 1
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "]" then return arr, i + 1 end
    if c ~= "," then decode_error("expected ',' or ']'", s, i) end
    i = skip_ws(s, i + 1)
  end
end

local function parse_object(s, i)
  i = i + 1 -- skip {
  local obj = {}
  i = skip_ws(s, i)
  if s:sub(i, i) == "}" then return obj, i + 1 end
  while true do
    if s:sub(i, i) ~= '"' then decode_error("expected string key", s, i) end
    local k; k, i = parse_string(s, i)
    i = skip_ws(s, i)
    if s:sub(i, i) ~= ":" then decode_error("expected ':'", s, i) end
    i = skip_ws(s, i + 1)
    local v; v, i = parse_value(s, i)
    obj[k] = v
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == "}" then return obj, i + 1 end
    if c ~= "," then decode_error("expected ',' or '}'", s, i) end
    i = skip_ws(s, i + 1)
  end
end

parse_value = function(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == '"' then return parse_string(s, i) end
  if c == "{" then return parse_object(s, i) end
  if c == "[" then return parse_array(s, i) end
  if c == "t" then return parse_literal(s, i, "true", true) end
  if c == "f" then return parse_literal(s, i, "false", false) end
  if c == "n" then return parse_literal(s, i, "null", nil) end
  return parse_number(s, i)
end

function M.decode(s)
  local v, i = parse_value(s, 1)
  i = skip_ws(s, i)
  if i <= #s then decode_error("trailing garbage", s, i) end
  return v
end

return M
