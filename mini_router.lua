-- mini_router.lua — micro-framework de rotas para Luvit (com param opcional + fallback de query)
local http = require("http")
local url = require("url")
local qs = require("querystring")
local json = require("json")

-- util: escapa padrões Lua
local function escape_lua_pattern(s)
    return (s:gsub("%%", "%%%%"):gsub("%^", "%%^"):gsub("%$", "%%$"):gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%.",
        "%%."):gsub("%[", "%%["):gsub("%]", "%%]"):gsub("%*", "%%*"):gsub("%+", "%%+"):gsub("%-", "%%-"):gsub("%?",
        "%%?"))
end

local function joinPaths(a, b)
    a = a or "";
    b = b or ""
    if a ~= "" and a:sub(-1) == "/" then
        a = a:sub(1, -2)
    end
    if b ~= "" and b:sub(1, 1) ~= "/" then
        b = "/" .. b
    end
    if a == "" then
        return (b == "" and "/" or b)
    end
    return a .. (b == "" and "" or b)
end

-- compila "/user/{id}" -> ^/user/?([^/]*)$ (captura "" quando ausente) e nomes {"id"}
local function compilePath(template)
    if template == "/" then
        return "^/$", {}
    end

    local names, parts, segments = {}, {}, {}

    -- coleta segmentos sem a barra inicial
    for seg in template:gsub("^/", ""):gmatch("[^/]+") do
        table.insert(segments, seg)
    end

    for i, seg in ipairs(segments) do
        local name = seg:match("^%{%s*([_%w]+)%s*%}$") -- "{id}"
        local is_last = (i == #segments)

        if name then
            table.insert(names, name)
            if is_last then
                -- último param é opcional: aceita "/user" e "/user/123"
                table.insert(parts, "/?([^/]*)")
            else
                -- params no meio continuam obrigatórios
                table.insert(parts, "/([^/]+)")
            end
        else
            -- literal (escapa metacaracteres de pattern, menos '/')
            table.insert(parts, "/" .. escape_lua_pattern(seg))
        end
    end

    local pat = "^" .. (#parts > 0 and table.concat(parts) or "/") .. "$"
    return pat, names
end

local function trim(s)
    return s and (s:match("^%s*(.-)%s*$")) or s
end

local function _set_header(out, k, v)
    if not k then
        return
    end
    out[string.lower(tostring(k))] = trim(v and tostring(v) or "")
end

local function normalizeHeaders(req)
    local out = {}
    if not req then
        return out
    end

    -- 1) Preferir rawHeaders: {"Authorization","Bearer xyz","Host","..."}
    local rh = req.rawHeaders
    if type(rh) == "table" and #rh > 0 and (#rh % 2 == 0) then
        for i = 1, #rh, 2 do
            _set_header(out, rh[i], rh[i + 1])
        end
        return out
    end

    local h = req.headers
    if type(h) ~= "table" then
        -- fallback: tentar API getHeader direta
        local v = type(req.getHeader) == "function" and req:getHeader("Authorization") or nil
        _set_header(out, "authorization", v)
        return out
    end

    local n = #h
    if n > 0 then
        if type(h[1]) == "string" then
            -- 2) Array de strings
            if n % 2 == 0 then
                -- alternando nome/valor
                for i = 1, n, 2 do
                    _set_header(out, h[i], h[i + 1])
                end
            else
                -- só nomes -> tenta getHeader
                for i = 1, n do
                    local name = h[i]
                    local v = type(req.getHeader) == "function" and req:getHeader(name) or nil
                    _set_header(out, name, v)
                end
            end
            return out
        elseif type(h[1]) == "table" then
            -- 3) Array de pares/tabelas: { {"Authorization","Bearer xyz"}, {"Host","..."} } ou { {name="Authorization",value="..."} }
            for i = 1, n do
                local e = h[i]
                if type(e) == "table" then
                    local k = e[1] or e.name or e.key or e.header or e.k
                    local v = e[2] or e.value or e.v
                    if not v and k and type(req.getHeader) == "function" then
                        v = req:getHeader(k)
                    end
                    _set_header(out, k, v)
                end
            end
            return out
        end
    end

    -- 4) Mapa padrão: { ["authorization"]="Bearer xyz" }
    for k, v in pairs(h) do
        if type(v) == "table" then
            v = v[1]
        end
        _set_header(out, k, v)
    end

    -- 5) Garantir authorization, se possível
    if not out["authorization"] and type(req.getHeader) == "function" then
        local v = req:getHeader("Authorization")
        if v then
            _set_header(out, "authorization", v)
        end
    end

    return out
end

local Server = {}
Server.__index = Server

function Server.new()
    return setmetatable({
        routes = {
            GET = {},
            POST = {},
            PUT = {},
            PATCH = {},
            DELETE = {},
            OPTIONS = {}
        },
        before = nil,
        _base_prefix = "", -- prefixo global fixo
        _prefix_stack = {} -- pilha para group()
    }, Server)
end

function Server:prefix(p) -- define prefixo global para próximas rotas
    self._base_prefix = p or ""
    return self
end

function Server:clear_prefix() -- limpa o prefixo global
    self._base_prefix = ""
    return self
end

function Server:group(p, fn) -- bloco com prefixo temporário (empilhável)
    table.insert(self._prefix_stack, p or "")
    local ok, err = pcall(fn, self)
    table.remove(self._prefix_stack)
    if not ok then
        error(err)
    end
    return self
end

local function addRoute(self, method, path, handler)
    local fullPath = joinPaths(self:_current_prefix(), path)
    local pattern, names = compilePath(fullPath)
    table.insert(self.routes[method], {
        pattern = pattern,
        names = names,
        handler = handler,
        path = fullPath
    })
end

function Server:get(path, handler)
    addRoute(self, "GET", path, handler)
end
function Server:post(path, handler)
    addRoute(self, "POST", path, handler)
end
function Server:put(path, handler)
    addRoute(self, "PUT", path, handler)
end
function Server:patch(path, handler)
    addRoute(self, "PATCH", path, handler)
end
function Server:delete(path, handler)
    addRoute(self, "DELETE", path, handler)
end
function Server:options(path, handler)
    addRoute(self, "OPTIONS", path, handler)
end

-- helpers de resposta
local function sendJson(res, status, obj)
    res:setHeader("Content-Type", "application/json")
    res:setHeader("Access-Control-Allow-Origin", "*")
    res:writeHead(status or 200)
    res:finish(json.stringify(obj))
end

local function sendText(res, status, str)
    res:setHeader("Content-Type", "text/plain; charset=utf-8")
    res:setHeader("Access-Control-Allow-Origin", "*")
    res:writeHead(status or 200)
    res:finish(str or "")
end

-- parse body se JSON
local function readBodyIfAny(req, cb)
    local chunks = {}
    req:on("data", function(chunk)
        chunks[#chunks + 1] = chunk
    end)
    req:on("end", function()
        local raw = table.concat(chunks)
        local ct = (req.headers["content-type"] or ""):lower()
        if ct:find("application/json", 1, true) and raw ~= "" then
            local ok, data = pcall(json.parse, raw)
            if ok then
                cb(raw, data)
            else
                cb(raw, nil, "invalid json")
            end
        else
            cb(raw, nil)
        end
    end)
end

local function matchRoute(routes, method, path)
    local list = routes[method] or {}
    for _, r in ipairs(list) do
        local caps = {path:match(r.pattern)}
        if #caps > 0 then
            local params = {}
            for i, name in ipairs(r.names) do
                local v = caps[i]
                if v == "" then
                    v = nil
                end -- "" (ausente) -> nil
                params[name] = v
            end
            return r.handler, params, r.path
        end
    end
    return nil
end

function Server:_current_prefix()
    local acc = self._base_prefix or ""
    for _, p in ipairs(self._prefix_stack) do
        acc = joinPaths(acc, p)
    end
    return acc
end

function Server:listen(port, host)
    host = host or "0.0.0.0"

    -- helpers locais
    local function trim(s)
        return s and (s:match("^%s*(.-)%s*$")) or s
    end
    local function lowerHeaders(h)
        local out = {}
        for k, v in pairs(h or {}) do
            -- força chave minúscula e valor string (algumas libs enviam arrays)
            out[string.lower(k)] = trim(type(v) == "table" and v[1] or tostring(v))
        end
        return out
    end

    http.createServer(function(req, res)
        -- CORS + preflight
        res:setHeader("Access-Control-Allow-Origin", "*")
        res:setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
        res:setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
        if req.method == "OPTIONS" then
            res:writeHead(204);
            return res:finish()
        end

        local parsed = url.parse(req.url or "/")
        local path = parsed.pathname or "/"
        local query = qs.parse(parsed.query or "")

        local handler, params, routePath = matchRoute(self.routes, req.method, path)
        if not handler then
            return sendJson(res, 404, {
                error = "route not found",
                method = req.method,
                path = path
            })
        end

        -- monta ctx ANTES do before()
        local headers = normalizeHeaders(req)
        local ctx = {
            req = req,
            res = res,
            method = req.method,
            path = path,
            route = routePath,
            params = params or {},
            query = query or {},
            headers = headers,
            json = function(status, obj)
                return sendJson(res, status, obj)
            end,
            text = function(status, str)
                return sendText(res, status, str)
            end
        }
        ctx.getHeader = function(name)
            return (name and headers[string.lower(name)]) or nil
        end
        ctx.getBearer = function()
            local auth = ctx.getHeader("authorization")
            if not auth or auth == "" then
                return nil
            end
            local scheme, token = auth:match("^(%S+)%s+(.+)$")
            if not scheme or scheme:lower() ~= "bearer" then
                return nil
            end
            return trim(token)
        end

        -- completa params ausentes com query (ex.: /user?id=1)
        for k, v in pairs(query) do
            if ctx.params[k] == nil then
                ctx.params[k] = v
            end
        end

        -- middleware global (auth etc.) ANTES de ler body
        if self.before then
            local ok, msg = self.before(ctx)
            if ok == false then
                return sendJson(res, 401, {
                    error = msg or "unauthorized"
                })
            end
        end

        -- lê body (se houver) e chama o handler
        readBodyIfAny(req, function(rawBody, jsonBody, jsonErr)
            ctx.raw, ctx.body, ctx.jsonErr = rawBody, jsonBody, jsonErr

            local ok, ret = pcall(handler, ctx)
            if not ok then
                return sendJson(res, 500, {
                    error = "handler error",
                    detail = tostring(ret)
                })
            end
            if ret == nil then
                return
            elseif type(ret) == "table" then
                return sendJson(res, 200, ret)
            else
                return sendText(res, 200, tostring(ret))
            end
        end)
    end):listen(port, host)

    print(("Server on http://%s:%d"):format(host, port))
    return self
end

return {
    new = Server.new
}
