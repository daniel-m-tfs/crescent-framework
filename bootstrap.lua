-- bootstrap.lua (na raiz do projeto)

-- Função para obter diretório do arquivo
local function this_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  -- Remove o nome do arquivo para obter apenas o diretório
  return src:match("(.*/)")  or "./"
end

-- Função para join paths (alternativa ao path.join)
local function path_join(...)
  local parts = {...}
  local result = table.concat(parts, "/")
  -- Remove barras duplicadas
  result = result:gsub("//+", "/")
  return result
end

local root = this_dir()

-- Evita duplicar caso bootstrap rode mais de uma vez
if not package.__crescent_bootstrapped then
  -- Paths do projeto
  package.path =
    path_join(root, "?.lua") .. ";" ..
    path_join(root, "?/init.lua") .. ";" ..
    package.path
  
  -- Adiciona LuaRocks paths para Lua 5.1 (LuaJIT)
  local home = os.getenv("HOME")
  if home then
    -- Path para módulos Lua (.lua)
    package.path = package.path .. ";" ..
      path_join(home, ".luarocks/share/lua/5.1/?.lua") .. ";" ..
      path_join(home, ".luarocks/share/lua/5.1/?/init.lua")
    
    -- Path para módulos C (.so)
    package.cpath = package.cpath .. ";" ..
      path_join(home, ".luarocks/lib/lua/5.1/?.so")
  end
  
  -- Paths globais do Homebrew (se existir)
  package.cpath = package.cpath .. ";/opt/homebrew/lib/lua/5.1/?.so"

  package.__crescent_bootstrapped = true
end

-- Pré-carrega módulos do Luvit (se disponíveis)
local success, http = pcall(require, "http")
if success then
  _G._http = http
  _G._url = require("url")
  _G._querystring = require("querystring")
  _G._json = require("json")
end