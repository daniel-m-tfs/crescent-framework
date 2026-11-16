-- Server-side state across requests, exposed as `ctx.session`.
--
--   app:use(session.middleware({
--       store = "cookie",            -- or "shared" (lua_shared_dict crescent_sessions)
--       name = "crescent_session",
--       max_age = 86400,             -- absolute lifetime (seconds)
--       idle_timeout = 3600,         -- expires after this long without requests
--       secret = nil,                -- default: config.secret_key / APP_KEY
--       secret_fallbacks = nil,      -- default: config.secret_key_fallbacks
--       cookie = { path = "/", same_site = "Lax", http_only = true, secure = ... },
--   }))
--
-- Cookie store: the whole session is JSON, encrypted and authenticated with
-- AES-256-GCM (key derived from the secret with HKDF-SHA256). Nothing lives on
-- the server, so `destroy` cannot revoke a copy of the cookie stolen earlier;
-- use the shared store when that matters.
-- Shared store: a random 128-bit id in a signed cookie, the data in an
-- ngx.shared dict with TTL = idle_timeout (shared by every worker, lost on
-- restart).
--
-- Set-Cookie is only written when the session changed (or on regenerate /
-- destroy), from a Response:before_flush hook, so it works even though the
-- action usually sends the response before `next()` returns.
local json = require("crescent.json")
local Cookie = require("crescent.cookie")
local Base64 = require("crescent.security.base64")
local Crypto = require("crescent.security.crypto")

local Session = {}
Session.__index = Session

Session.MAX_COOKIE_SIZE = 4096

local FLASH_KEY = "_flash"

local function now()
    return Crypto.now()
end

-- Session API -------------------------------------------------------------

function Session:get(key)
    return self.data[key]
end

function Session:set(key, value)
    assert(type(key) == "string" and key ~= FLASH_KEY, "invalid session key")
    self.data[key] = value
    self.changed = true
    return self
end

function Session:delete(key)
    if self.data[key] ~= nil then
        self.data[key] = nil
        self.changed = true
    end
    return self
end

-- Removes every value but keeps the session (and its id).
function Session:clear()
    self.data = {}
    self.flash_in = {}
    self.changed = true
    return self
end

-- New id (shared store) / new ciphertext, same data. Call it after login and
-- privilege changes to prevent session fixation.
function Session:regenerate()
    self.regenerated = true
    self.changed = true
    return self
end

-- Deletes the session on the server and expires the cookie. Values set
-- afterwards (e.g. a "logged out" flash) start a brand-new session.
function Session:destroy()
    self.data = {}
    self.flash_in = {}
    self.destroyed = true
    self.changed = false
    self.regenerated = false
    return self
end

-- A flash value is readable (once) on the next request only.
function Session:flash(key, value)
    local pending = self.data[FLASH_KEY]
    if type(pending) ~= "table" then
        pending = {}
        self.data[FLASH_KEY] = pending
    end
    pending[key] = value
    self.changed = true
    return self
end

function Session:get_flash(key)
    return self.flash_in[key]
end

function Session:is_new()
    return self.fresh == true
end

-- Key derivation and encryption --------------------------------------------

local key_cache = {}

-- HKDF-SHA256 (RFC 5869) for a single 32-byte block.
local function hkdf(secret, salt, info)
    local prk = Crypto.hmac("sha256", salt, secret)
    return Crypto.hmac("sha256", prk, info .. "\1")
end

local function encryption_key(secret)
    local key = key_cache[secret]
    if not key then
        key = hkdf(secret, "crescent.session.salt", "crescent.session.aes-256-gcm")
        key_cache[secret] = key
    end
    return key
end

local VERSION = "\1"

local function seal(secret, plaintext, aad)
    local cipher = assert(require("resty.openssl.cipher").new("aes-256-gcm"))
    local iv = Crypto.random_bytes(12)
    local ciphertext, err = cipher:encrypt(encryption_key(secret), iv, plaintext, false, aad)
    if not ciphertext then error("session encryption failed: " .. tostring(err)) end
    local tag = assert(cipher:get_aead_tag(16))
    return Base64.url_encode(VERSION .. iv .. tag .. ciphertext)
end

local function unseal(secrets, token, aad)
    local raw = Base64.url_decode(token)
    if not raw or #raw < 29 or raw:sub(1, 1) ~= VERSION then return nil end
    local iv, tag, ciphertext = raw:sub(2, 13), raw:sub(14, 29), raw:sub(30)
    for _, secret in ipairs(secrets) do
        local cipher = assert(require("resty.openssl.cipher").new("aes-256-gcm"))
        local plaintext = cipher:decrypt(encryption_key(secret), iv, ciphertext, false, aad, tag)
        if plaintext then return plaintext end
    end
    return nil
end

Session._seal, Session._unseal = seal, unseal

-- Payload: { d = data, c = created_at, a = last_access }.
local function decode_payload(text)
    if not text then return nil end
    local payload = json.decode(text)
    if type(payload) ~= "table" or type(payload.d) ~= "table"
        or type(payload.c) ~= "number" or type(payload.a) ~= "number" then
        return nil
    end
    return payload
end

local function encode_payload(session)
    local text, err = json.encode({ d = session.data, c = session.created, a = session.accessed })
    if not text then error("session data is not JSON-serializable: " .. tostring(err)) end
    return text
end

-- Stores ------------------------------------------------------------------
-- load(session) -> payload | nil; save(session); destroy(session)

local CookieStore = {}
CookieStore.__index = CookieStore

function CookieStore:load(session)
    local raw = session.ctx:cookie(self.settings.name)
    if not raw then return nil end
    local payload = decode_payload(unseal(session.secrets, raw, self.settings.name))
    if not payload then session.stale = true end
    return payload
end

function CookieStore:save(session)
    local settings = self.settings
    local value = seal(session.secrets[1], encode_payload(session), settings.name)
    local header = Cookie.serialize(settings.name, value, session:cookie_options())
    if #header > Session.MAX_COOKIE_SIZE then
        error(string.format(
            "session cookie is %d bytes, above the %d-byte browser limit; store less data in the session "
                .. "or use store = \"shared\"", #header, Session.MAX_COOKIE_SIZE))
    end
    session.ctx:set_cookie(settings.name, value, session:cookie_options())
end

function CookieStore:destroy() end

local SharedStore = {}
SharedStore.__index = SharedStore

function SharedStore:dict()
    local shared = ngx and ngx.shared
    local dict = shared and shared[self.settings.dict]
    if not dict then
        error("session store \"shared\" requires `lua_shared_dict " .. self.settings.dict .. "` in nginx.conf", 3)
    end
    return dict
end

local function shared_key(id)
    return "session:" .. id
end

function SharedStore:load(session)
    local raw = session.ctx:cookie(self.settings.name)
    if not raw then return nil end
    local id = Cookie.unsign(self.settings.name, raw, session.secrets)
    if not id or not id:match("^[A-Za-z0-9_%-]+$") then
        session.stale = true
        return nil
    end
    local payload = decode_payload(self:dict():get(shared_key(id)))
    if not payload then
        session.stale = true
        return nil
    end
    session.id = id
    return payload
end

function SharedStore:save(session)
    local dict = self:dict()
    local new_id = session.id == nil or session.regenerated
    if new_id then
        if session.id then dict:delete(shared_key(session.id)) end
        session.id = Base64.url_encode(Crypto.random_bytes(16))
    end
    local ttl = self.settings.idle_timeout or self.settings.max_age or 0
    local ok, err = dict:safe_set(shared_key(session.id), encode_payload(session), ttl)
    if not ok then error("unable to store session: " .. tostring(err)) end
    if new_id then
        local signed = Cookie.sign(self.settings.name, session.id, session.secrets[1])
        session.ctx:set_cookie(self.settings.name, signed, session:cookie_options())
    end
end

-- Extends the TTL without rewriting the cookie.
function SharedStore:touch(session)
    local dict = self:dict()
    local ttl = self.settings.idle_timeout
    if ttl and session.id and dict.expire then dict:expire(shared_key(session.id), ttl) end
end

function SharedStore:destroy(session)
    if session.id then self:dict():delete(shared_key(session.id)) end
end

-- Lifecycle ---------------------------------------------------------------

function Session:cookie_options()
    local options = {}
    for key, value in pairs(self.settings.cookie) do options[key] = value end
    if options.max_age == nil and self.settings.max_age then
        options.max_age = self.settings.max_age - (now() - self.created)
    end
    return options
end

local function expired(settings, payload, time)
    if settings.max_age and time - payload.c >= settings.max_age then return true end
    if settings.idle_timeout and time - payload.a >= settings.idle_timeout then return true end
    return false
end

function Session.load(ctx, settings, store)
    local time = now()
    local session = setmetatable({
        ctx = ctx,
        settings = settings,
        store = store,
        secrets = Cookie.secrets(ctx.config, settings.secret, settings.secret_fallbacks),
        data = {},
        flash_in = {},
        created = time,
        accessed = time,
    }, Session)
    local payload = store:load(session)
    if payload and expired(settings, payload, time) then
        store:destroy(session)
        session.id = nil
        session.stale = true
        payload = nil
    end
    if not payload then
        session.fresh = true
        return session
    end
    session.data = payload.d
    session.created = payload.c
    session.accessed = payload.a
    local flash = session.data[FLASH_KEY]
    if flash ~= nil then
        session.data[FLASH_KEY] = nil
        session.flash_in = type(flash) == "table" and flash or {}
        session.changed = true
    end
    -- Refresh the idle timer every `touch_interval` seconds instead of on
    -- every request, which would rewrite the cookie each time.
    if settings.idle_timeout and time - session.accessed >= settings.touch_interval then
        session.accessed = time
        session.touched = true
    end
    return session
end

-- Runs once, right before the response is flushed.
function Session:commit()
    if self.committed then return end
    self.committed = true
    local store, settings = self.store, self.settings
    local had_cookie = not self.fresh or self.stale
    if self.destroyed then
        store:destroy(self)
        self.id = nil
        self.created = now()
        self.fresh = true
        if not (self.changed and next(self.data) ~= nil) then
            if had_cookie then self.ctx:clear_cookie(settings.name, settings.cookie) end
            return
        end
    end
    if self.changed or self.regenerated then
        if self.fresh and next(self.data) == nil then
            if had_cookie then self.ctx:clear_cookie(settings.name, settings.cookie) end
            return
        end
        self.accessed = now()
        return store:save(self)
    end
    if self.touched then
        if store.touch then return store:touch(self) end
        return store:save(self)
    end
    if self.stale then self.ctx:clear_cookie(settings.name, settings.cookie) end
end

-- Middleware --------------------------------------------------------------

local STORES = { cookie = CookieStore, shared = SharedStore }

function Session.middleware(options)
    options = options or {}
    local store_name = options.store or "cookie"
    local Store = STORES[store_name]
    if not Store then error("unknown session store: " .. tostring(store_name), 2) end

    local settings = {
        name = options.name or "crescent_session",
        max_age = options.max_age == nil and 86400 or options.max_age,
        idle_timeout = options.idle_timeout == nil and 3600 or options.idle_timeout,
        secret = options.secret,
        secret_fallbacks = options.secret_fallbacks,
        dict = options.dict or "crescent_sessions",
        cookie = {},
    }
    if settings.max_age == false then settings.max_age = nil end
    if settings.idle_timeout == false then settings.idle_timeout = nil end
    for _, key in ipairs({ "max_age", "idle_timeout" }) do
        local value = settings[key]
        if value ~= nil and (type(value) ~= "number" or value <= 0) then
            error("session " .. key .. " must be a positive number or false", 2)
        end
    end
    if not Cookie.valid_name(settings.name) then error("invalid session cookie name", 2) end
    settings.touch_interval = options.touch_interval
        or (settings.idle_timeout and math.min(60, math.floor(settings.idle_timeout / 4))) or 0
    for key, value in pairs(options.cookie or {}) do settings.cookie[key] = value end
    settings.cookie.signed = nil
    if settings.cookie.http_only == nil then settings.cookie.http_only = true end
    if store_name == "shared" and settings.idle_timeout == nil and settings.max_age == nil then
        error("the shared session store needs idle_timeout or max_age (entry TTL)", 2)
    end

    local store = setmetatable({ settings = settings }, Store)
    if store_name == "shared" then store:dict() end
    if options.secret ~= nil then Cookie.secrets({}, options.secret, options.secret_fallbacks) end

    return function(ctx, next)
        local session = Session.load(ctx, settings, store)
        ctx.session = session
        ctx.res:before_flush(function() session:commit() end)
        return next()
    end
end

return Session
