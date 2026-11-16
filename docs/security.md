# Segurança e autenticação

Módulos:

| Módulo | Função |
| --- | --- |
| `crescent.security.jwt` | JWT HS256/HS384/HS512, revogação compartilhada entre workers |
| `crescent.security.password` | hash de senha PBKDF2-HMAC-SHA256 (OpenSSL nativo) |
| `crescent.security.base64` | Base64 / Base64URL estritos |
| `crescent.middleware.auth` | Bearer, Basic, API key, JWT, `protect` |
| `crescent.middleware.cors` | CORS com allowlist e preflight |
| `crescent.middleware.security_headers` | headers de segurança |
| `crescent.middleware.rate_limit` | rate limit entre workers (`ngx.shared`) |
| `crescent.middleware.session` | sessões (cookie AES-256-GCM ou `ngx.shared`) — ver [web.md](web.md#sessões) |
| `crescent.middleware.csrf` | proteção CSRF com token na sessão — ver [web.md](web.md#csrf) |

> Aplicações com formulários e login por cookie: use sessões + CSRF
> ([docs/web.md](web.md)), chame `ctx.session:regenerate()` após o login e
> mantenha `secret_key`/`APP_KEY` fora do repositório. Cookies assinados,
> uploads e o limite de 4 KB do cookie de sessão também estão descritos lá.

Middleware segue a convenção do framework: `function(ctx, next) ... return next() end`.
Para bloquear, o middleware responde (`return ctx:error(...)`) sem chamar `next`.
Erros sempre trazem um `code` estável (`missing_credentials`, `invalid_token`,
`token_expired`, `token_revoked`, `rate_limited`, `cors_origin_not_allowed`...).

## Senhas

```lua
local password = require("crescent.security.password")

local stored = password.hash("s3cr3t")            -- "600000$<salt hex>$<hash hex>"
if password.verify(input, user.password_hash) then
    if password.needs_rehash(user.password_hash) then
        user.password_hash = password.hash(input) -- atualiza hashes antigos no login
    end
end
```

- Formato `iteracoes$salthex$hashhex` (salt de 16 bytes, chave de 32 bytes),
  idêntico ao `hash.encrypt` do Crescent original: hashes antigos continuam válidos.
- Padrão: **600.000 iterações** (OWASP). O PBKDF2 roda em C (OpenSSL), mas
  ainda é síncrono dentro do worker: medido ~64 ms por hash/verify
  (100k ≈ 11 ms). Ajuste com `PASSWORD_HASH_ITERATIONS` em hardware lento e
  aplique rate limit nas rotas de login.
- `verify` nunca lança erro: hash corrompido ou senha vazia retornam `false`.

## JWT

```lua
local jwt = require("crescent.security.jwt")

local token = jwt.sign({ user_id = 1 }, secret, { expires_in = 900, issuer = "api" })
local ok, payload_or_message, code = jwt.verify(token, secret, {
    issuer = "api",
    audience = { "web", "mobile" },  -- string ou lista
    algorithms = { "HS256" },         -- padrão; "none" nunca é aceito
    leeway = 30,
})
```

- O algoritmo é fixado pelo verificador (`algorithms`), nunca pelo token.
- Assinatura comparada em tempo constante; `exp`/`nbf`/`iat` precisam ser números.
- `sign` gera um `jti` aleatório (desative com `{ jti = false }`).
- `create_access_token` marca `typ = "access"` (15 min); `create_refresh_token`
  marca `typ = "refresh"` (30 dias). `verify(..., { token_type = "access" })`
  rejeita refresh tokens; `token_type = "refresh"` aceita apenas refresh.
- `jwt.decode` **não** verifica nada: use só para depuração.

### Revogação

```lua
jwt.revoke(payload)          -- ou jwt.revoke(jti, exp)
jwt.unrevoke(jti)
```

A lista de revogados fica em `ngx.shared.crescent_jwt` (ou, se ele não
existir, `crescent_limits`; prefixo `jwt:revoked:`), visível para todos os workers; cada entrada expira junto
com o token. Para usar outro armazenamento (Redis, banco), implemente
`{ revoke(jti, ttl), is_revoked(jti), unrevoke(jti) }` e chame
`jwt.set_revocation_store(store)` ou passe `{ revocation = store }`.
Em produção, prefira um dict dedicado (`jwt.shared_store("crescent_jwt")`)
para que contadores de rate limit não disputem memória com revogações.

## Autenticação

```lua
local auth = require("crescent.middleware.auth")

-- global
app:use(auth.jwt())  -- secret padrão: JWT_SECRET (erro na construção se ausente)

-- por rota
app:get("/me", auth.protect(auth.jwt(), function(ctx)
    return ctx:json(200, ctx.state.user)
end))

-- vários middlewares numa rota
app:post("/admin", auth.protect({ auth.jwt(), require_admin }, action))
```

`auth.jwt(options)`: `secret`, `issuer`, `audience`, `algorithms`, `leeway`,
`revocation`, `optional`, `get_user(payload, ctx)` (retornar `nil` → 401).
Em sucesso define `ctx.state.user` e `ctx.state.jwt`. Refresh tokens são
recusados.

```lua
auth.bearer(function(token, ctx) return token == "x", { id = 1 } end)
auth.basic(function(user, pass, ctx)
    return auth.secure_compare(pass, expected), { name = user }
end, { realm = "Admin" })
auth.api_key("X-Api-Key", function(key, ctx) return lookup(key) ~= nil, lookup(key) end)
auth.jwt({ optional = true })   -- define o usuário se houver token válido, nunca bloqueia
```

- Headers de credencial acima de 8 KB são recusados.
- Basic: base64 estrito; a senha pode conter `:`.
- Validators recebem `(…, ctx)` e retornam `ok, user_ou_mensagem`.

Tokens:

```lua
local pair = auth.generate_token_pair(user, { access_expires_in = 900 })
-- { access_token, refresh_token, token_type = "Bearer", expires_in, refresh_expires_in }

app:post("/auth/refresh", function(ctx)
    local ok, payload = auth.verify_refresh_token(ctx.body.refresh_token)
    if not ok then return ctx:error(401, "invalid token", nil, "invalid_token") end
    auth.revoke_token(payload)  -- rotação: o refresh antigo deixa de valer
    return ctx:json(200, auth.generate_token_pair(payload.user_id))
end)
```

## CORS

```lua
local cors = require("crescent.middleware.cors")

app:use(cors.create({
    origins = { "https://app.example.com" },  -- ou "*" ou function(origin, ctx)
    methods = { "GET", "POST", "PUT", "DELETE" },
    allowed_headers = { "Content-Type", "Authorization" },
    expose_headers = { "X-Request-Id" },
    credentials = true,
    max_age = 600,
}))
app:use(cors.strict({ "https://app.example.com" }))  -- credenciais + 403 para outras origens
```

- Preflight (`OPTIONS` + `Access-Control-Request-Method`) é respondido com 204
  pelo middleware, antes do roteamento; não é preciso criar rotas OPTIONS.
  Método ou header não permitido → 403.
- A origem aceita é refletida com `Vary: Origin`; `credentials` com `"*"` é
  recusado na construção.
- Registre o CORS antes da autenticação, senão preflights recebem 401.

## Headers de segurança

```lua
local security_headers = require("crescent.middleware.security_headers")

app:use(security_headers.create({
    hsts = true,                                -- só se o site for 100% HTTPS
    csp = "default-src 'self'; frame-ancestors 'none'",
}))
```

Padrões: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: strict-origin-when-cross-origin`. Opções:
`frame_options`, `referrer_policy`, `content_type_options`, `hsts`
(`true` ou `{ max_age, include_subdomains, preload }`), `csp`,
`permissions_policy`, `cross_origin_opener_policy` e `headers` (extras;
`false` remove).

## Rate limit

```lua
local rate_limit = require("crescent.middleware.rate_limit")

app:use(rate_limit.create({ limit = 100, window = 60 }))
app:post("/login", auth.protect(
    rate_limit.create({ limit = 5, window = 60, prefix = "rl:login:" }), login))
```

- Janela fixa em `ngx.shared.crescent_limits` (compartilhada entre workers);
  erro na construção se o dict não existir.
- Resposta 429 (`rate_limited`) com `Retry-After`; respostas trazem
  `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` (epoch).
- Chave padrão: `ctx.remote_addr`. Atrás de proxy, configure o módulo
  `realip` do nginx (`set_real_ip_from`, `real_ip_header X-Forwarded-For`);
  **nunca** use o `X-Forwarded-For` cru como chave, ele é forjável.
- `key = function(ctx) ... end` personaliza; retornar `nil` isenta a requisição.
- Se o dict falhar (memória cheia), a requisição segue (fail open) e o erro é logado.
