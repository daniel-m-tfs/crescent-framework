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
  package.path =
    path.join(root, "?.lua") .. ";" ..
    path.join(root, "?/init.lua") .. ";" ..
    package.path

  package.__crescent_bootstrapped = true
end
-- Pré-carrega módulos do Luvit
_G._http = require("http")
_G._url = require("url")
_G._querystring = require("querystring")
_G._json = require("json")