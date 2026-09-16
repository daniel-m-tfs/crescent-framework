-- crescent/utils/base64.lua
-- Base64 (RFC 4648) e Base64URL, implementação pura em Lua

local M = {}

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64lookup = {}
for i = 1, #b64chars do
  b64lookup[b64chars:sub(i, i)] = i - 1
end
-- "=" NÃO entra no lookup como um caractere de dado válido (era o bug: com
-- b64lookup["="]=0, um "=" fora de posição virava silenciosamente um "A" em
-- vez de invalidar o decode). É tratado explicitamente em M.decode() como
-- padding, só permitido nas duas últimas posições do ÚLTIMO grupo de 4.

function M.encode(data)
  local out = {}
  local len = #data
  local i = 1
  while i <= len do
    local a = data:byte(i) or 0
    local b = data:byte(i + 1) or 0
    local c = data:byte(i + 2) or 0
    local triple = a * 65536 + b * 256 + c

    local s1 = math.floor(triple / 262144) % 64
    local s2 = math.floor(triple / 4096) % 64
    local s3 = math.floor(triple / 64) % 64
    local s4 = triple % 64

    out[#out + 1] = b64chars:sub(s1 + 1, s1 + 1)
    out[#out + 1] = b64chars:sub(s2 + 1, s2 + 1)

    if i + 1 <= len then
      out[#out + 1] = b64chars:sub(s3 + 1, s3 + 1)
    else
      out[#out + 1] = "="
    end

    if i + 2 <= len then
      out[#out + 1] = b64chars:sub(s4 + 1, s4 + 1)
    else
      out[#out + 1] = "="
    end

    i = i + 3
  end
  return table.concat(out)
end

function M.decode(data)
  data = data:gsub("%s", "")
  if #data == 0 then return "" end
  if (#data % 4) ~= 0 then return nil end

  local out = {}
  local len = #data
  local i = 1
  while i <= len do
    local is_last_group = (i + 3 == len)
    local ch1 = data:sub(i, i)
    local ch2 = data:sub(i + 1, i + 1)
    local ch3 = data:sub(i + 2, i + 2)
    local ch4 = data:sub(i + 3, i + 3)

    -- "=" só é válido nas duas últimas posições do ÚLTIMO grupo de 4 (e só
    -- como sufixo: "X=" ou "==", nunca "=X"). Qualquer outra ocorrência
    -- invalida o decode em vez de ser silenciosamente tratada como dado.
    if ch1 == "=" or ch2 == "=" then return nil end
    if (ch3 == "=" or ch4 == "=") and not is_last_group then return nil end
    if ch3 == "=" and ch4 ~= "=" then return nil end

    local c1 = b64lookup[ch1]
    local c2 = b64lookup[ch2]
    local c3 = (ch3 == "=") and 0 or b64lookup[ch3]
    local c4 = (ch4 == "=") and 0 or b64lookup[ch4]
    if c1 == nil or c2 == nil or c3 == nil or c4 == nil then return nil end

    local triple = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
    local a = math.floor(triple / 65536) % 256
    local b = math.floor(triple / 256) % 256
    local c = triple % 256

    out[#out + 1] = string.char(a)
    if ch3 ~= "=" then out[#out + 1] = string.char(b) end
    if ch4 ~= "=" then out[#out + 1] = string.char(c) end

    i = i + 4
  end
  return table.concat(out)
end

function M.url_encode(raw)
  local b64 = M.encode(raw)
  b64 = b64:gsub("%+", "-"):gsub("/", "_"):gsub("=", "")
  return b64
end

function M.url_decode(s)
  s = s:gsub("%-", "+"):gsub("_", "/")
  local pad = #s % 4
  if pad == 2 then s = s .. "=="
  elseif pad == 3 then s = s .. "="
  elseif pad ~= 0 then return nil end
  return M.decode(s)
end

return M
