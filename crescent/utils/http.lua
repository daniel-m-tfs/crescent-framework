-- HTTP Client Library for Crescent Framework
-- Provides an easy-to-use interface for consuming external APIs (axios-like)
--
-- Reescrito do zero: a versão anterior dependia de LuaSocket/LuaSec/cjson
-- ("socket.http", "ssl.https", "ltn12", "cjson"), nenhum instalado nem
-- declarado em package.lua — o módulo não carregava de jeito nenhum. Além
-- disso LuaSocket é bloqueante, o oposto do runtime assíncrono do Luvit
-- (libuv, single-thread) que o resto do framework assume: uma chamada HTTP
-- externa lenta travaria TODAS as outras conexões sendo servidas.
--
-- Esta versão usa os módulos nativos assíncronos do Luvit (http/https,
-- iguais aos que bootstrap.lua já pré-carrega em _G._http/_G._url), com uma
-- pequena camada de coroutine pra expor uma API que parece síncrona sem
-- bloquear o event loop. Precisa ser chamada de dentro de uma coroutine
-- (handlers de rota já rodam em uma, então isso funciona transparentemente
-- em uso normal).

-- "http"/"url"/"json" resolvem normalmente via require() mesmo daqui de
-- dentro (são os mesmos que bootstrap.lua pré-carrega). "https" e "timer"
-- NÃO resolvem de forma confiável quando requeridos a partir de um módulo
-- carregado via o resolvedor pontilhado do Luvit (require("crescent.x.y"))
-- — por isso dependem de bootstrap.lua já ter rodado e populado
-- _G._https/_G._timer. Ver comentário em bootstrap.lua.
local http = _G._http or require("http")
local urlLib = _G._url or require("url")
local json = _G._json or require("json")

local function get_https()
    if _G._https then return _G._https end
    error("Módulo 'https' não disponível — rode require(\"bootstrap\") (ou require(\"../bootstrap\")," ..
          " conforme a profundidade do arquivo) antes de usar crescent.utils.http com URLs https://")
end

local function get_timer()
    if _G._timer then return _G._timer end
    error("Módulo 'timer' não disponível — rode require(\"bootstrap\") antes de usar crescent.utils.http")
end

local HttpClient = {}
HttpClient.__index = HttpClient

-- Create a new HTTP client instance
function HttpClient.new(config)
    local self = setmetatable({}, HttpClient)
    self.baseURL = config and config.baseURL or ""
    self.timeout = config and config.timeout or 30 -- segundos
    self.headers = config and config.headers or {}
    return self
end

-- Merge two tables
local function merge_tables(t1, t2)
    local result = {}
    for k, v in pairs(t1 or {}) do
        result[k] = v
    end
    for k, v in pairs(t2 or {}) do
        result[k] = v
    end
    return result
end

-- Build query string from table
local function build_query_string(params)
    if not params then return "" end

    local parts = {}
    for key, value in pairs(params) do
        table.insert(parts, tostring(key) .. "=" .. tostring(value))
    end

    if #parts == 0 then return "" end
    return "?" .. table.concat(parts, "&")
end

-- Faz a requisição de baixo nível via http/https nativo do Luvit, expondo
-- como uma chamada que "parece síncrona" via coroutine.yield/resume — sem
-- bloquear o event loop (outras conexões continuam sendo atendidas
-- normalmente enquanto esta coroutine está suspensa esperando resposta).
local function do_request(mod, request_options, request_body, timeout_seconds)
    local co, is_main = coroutine.running()
    if not co or is_main then
        error("crescent.utils.http precisa ser chamado de dentro de uma coroutine (ex: dentro de um handler de rota)")
    end

    local settled = false
    local result, err

    local function finish(res, e)
        if settled then return end
        settled = true
        result, err = res, e
        local ok, resume_err = coroutine.resume(co)
        if not ok then
            print("⚠️ Erro ao resumir coroutine em crescent.utils.http:", resume_err)
        end
    end

    local timer = get_timer()
    local timeout_timer
    if timeout_seconds and timeout_seconds > 0 then
        timeout_timer = timer.setTimeout(timeout_seconds * 1000, function()
            finish(nil, "Request timed out after " .. timeout_seconds .. "s")
        end)
    end

    local req = mod.request(request_options, function(res)
        local chunks = {}
        res:on("data", function(chunk) table.insert(chunks, chunk) end)
        res:on("end", function()
            if timeout_timer then timer.clearTimer(timeout_timer) end
            finish({
                statusCode = res.statusCode,
                headers = res.headers,
                body = table.concat(chunks)
            }, nil)
        end)
        res:on("error", function(e)
            if timeout_timer then timer.clearTimer(timeout_timer) end
            finish(nil, e)
        end)
    end)

    req:on("error", function(e)
        if timeout_timer then timer.clearTimer(timeout_timer) end
        finish(nil, e)
    end)

    if request_body and request_body ~= "" then
        req:write(request_body)
    end
    req:done()

    if not settled then
        coroutine.yield()
    end

    return result, err
end

-- Perform HTTP request
function HttpClient:request(config)
    local url = config.url or ""

    -- Add baseURL if present
    if self.baseURL ~= "" and not url:match("^https?://") then
        url = self.baseURL .. url
    end

    -- Add query params
    if config.params then
        url = url .. build_query_string(config.params)
    end

    local parsed = urlLib.parse(url)
    if not parsed or not parsed.hostname then
        return nil, { error = true, message = "Invalid URL: " .. tostring(url) }
    end

    -- Prepare headers
    local headers = merge_tables(self.headers, config.headers)

    -- Prepare request body
    local request_body = ""
    if config.data then
        if type(config.data) == "table" then
            request_body = json.stringify(config.data)
            headers["content-type"] = headers["content-type"] or "application/json"
        else
            request_body = tostring(config.data)
        end
        headers["content-length"] = tostring(#request_body)
    end

    local header_list = {}
    for k, v in pairs(headers) do
        table.insert(header_list, { k, tostring(v) })
    end

    local is_https_url = parsed.protocol == "https"
    local mod = is_https_url and get_https() or http

    local request_options = {
        host = parsed.hostname,
        port = parsed.port and tonumber(parsed.port) or (is_https_url and 443 or 80),
        path = parsed.path or "/",
        method = config.method or "GET",
        headers = header_list
    }

    local raw, err = do_request(mod, request_options, request_body, config.timeout or self.timeout)

    if not raw then
        return nil, {
            error = true,
            message = "Request failed: " .. tostring(err),
            config = config
        }
    end

    -- Tenta parsear como JSON; se não for JSON, devolve o corpo cru
    local data = raw.body
    local ok, parsed_body = pcall(json.parse, raw.body)
    if ok then
        data = parsed_body
    end

    local result = {
        data = data,
        status = raw.statusCode,
        headers = raw.headers or {},
        config = config
    }

    if raw.statusCode < 200 or raw.statusCode >= 400 then
        result.error = true
        result.message = "Request failed with status " .. raw.statusCode
        return nil, result
    end

    return result, nil
end

-- Convenience methods
function HttpClient:get(url, config)
    config = config or {}
    config.url = url
    config.method = "GET"
    return self:request(config)
end

function HttpClient:post(url, data, config)
    config = config or {}
    config.url = url
    config.method = "POST"
    config.data = data
    return self:request(config)
end

function HttpClient:put(url, data, config)
    config = config or {}
    config.url = url
    config.method = "PUT"
    config.data = data
    return self:request(config)
end

function HttpClient:patch(url, data, config)
    config = config or {}
    config.url = url
    config.method = "PATCH"
    config.data = data
    return self:request(config)
end

function HttpClient:delete(url, config)
    config = config or {}
    config.url = url
    config.method = "DELETE"
    return self:request(config)
end

function HttpClient:head(url, config)
    config = config or {}
    config.url = url
    config.method = "HEAD"
    return self:request(config)
end

function HttpClient:options(url, config)
    config = config or {}
    config.url = url
    config.method = "OPTIONS"
    return self:request(config)
end

-- Create default instance
local default_instance = HttpClient.new()

-- Export module with default instance methods
local exports = {
    create = function(config)
        return HttpClient.new(config)
    end,

    request = function(config)
        return default_instance:request(config)
    end,

    get = function(url, config)
        return default_instance:get(url, config)
    end,

    post = function(url, data, config)
        return default_instance:post(url, data, config)
    end,

    put = function(url, data, config)
        return default_instance:put(url, data, config)
    end,

    patch = function(url, data, config)
        return default_instance:patch(url, data, config)
    end,

    delete = function(url, config)
        return default_instance:delete(url, config)
    end,

    head = function(url, config)
        return default_instance:head(url, config)
    end,

    options = function(url, config)
        return default_instance:options(url, config)
    end
}

return exports
