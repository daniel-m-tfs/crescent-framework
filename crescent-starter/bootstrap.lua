-- bootstrap.lua (na raiz do projeto)
local path = require("path")

local function this_dir()
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  return path.dirname(src)
end

local root = this_dir()

-- Evita duplicar caso bootstrap rode mais de uma vez
if not package.__crescent_bootstrapped then
  -- Paths do projeto
  package.path =
    path.join(root, "?.lua") .. ";" ..
    path.join(root, "?/init.lua") .. ";" ..
    package.path
  
  -- Adiciona LuaRocks paths para Lua 5.1 (LuaJIT)
  local home = os.getenv("HOME")
  if home then
    -- Path para módulos Lua (.lua)
    package.path = package.path .. ";" ..
      path.join(home, ".luarocks/share/lua/5.1/?.lua") .. ";" ..
      path.join(home, ".luarocks/share/lua/5.1/?/init.lua")
    
    -- Path para módulos C (.so)
    package.cpath = package.cpath .. ";" ..
      path.join(home, ".luarocks/lib/lua/5.1/?.so")
  end
  
  -- Paths globais do Homebrew (se existir)
  package.cpath = package.cpath .. ";/opt/homebrew/lib/lua/5.1/?.so"

  package.__crescent_bootstrapped = true
end
-- Pré-carrega módulos do Luvit
_G._http = require("http")
_G._url = require("url")
_G._querystring = require("querystring")
_G._json = require("json")