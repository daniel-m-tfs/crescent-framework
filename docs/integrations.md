# Integrações: HTTP e e-mail

Ambos os módulos usam cosockets do OpenResty (não bloqueiam o worker). Funcionam
nas fases content/access/rewrite, em `ngx.timer` e em scripts `resty`; **não**
funcionam em `init_by_lua`, `set_by_lua`, filtros de header/body nem `log_by_lua`.

## Configuração do nginx

Conexões de saída resolvem DNS pelo nginx e verificam TLS com o bundle de CAs
configurado. Sem isso, nomes não resolvem e `ssl_verify` falha:

```nginx
http {
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;
    lua_ssl_trusted_certificate /etc/ssl/cert.pem;   # Debian: /etc/ssl/certs/ca-certificates.crt
    lua_ssl_verify_depth 3;
}
```

Dependências: `lua-resty-http` e `lua-resty-mail` (instaladas por `./deps.sh`).

## Cliente HTTP — `crescent.http_client`

API no estilo axios sobre `lua-resty-http`.

```lua
local HttpClient = require("crescent.http_client")

local api = HttpClient.new({
    base_url = "https://api.example.com/v1",
    timeout = 5,                         -- segundos (padrão 30)
    headers = { Authorization = "Bearer " .. token },
    max_response_size = 1024 * 1024,     -- bytes (padrão 10 MiB)
})

local res, err = api:get("/users", { params = { page = 2 } })
if not res then
    return ctx:error(502, "upstream failed", ctx.debug and err.message or nil, "upstream_error")
end
return ctx:json(200, res.data)
```

- Métodos: `get(url, config)`, `delete`, `head`, `options`; `post(url, data, config)`, `put`, `patch`; `request{ url, method, params, data, headers, timeout, max_response_size }`.
- `data` em tabela é enviado como JSON (`Content-Type: application/json`); string é enviada como está.
- Resposta: `{ status, headers, body, data }`. `data` é o JSON decodificado (via `crescent.json`) quando a resposta é JSON; senão, o corpo bruto.
- Erros retornam `nil, err` (`err.message`, `tostring(err)`). Status `>= 400` também retorna `nil, err`, com `err.status`, `err.headers`, `err.body` e `err.data`.
- Segurança: `ssl_verify` ligado por padrão; o corpo é lido em streaming e a conexão é abortada ao passar de `max_response_size`; headers com CR/LF são rejeitados; apenas `http`/`https`; credenciais na URL não são aceitas; redirecionamentos não são seguidos.
- Conexões voltam para o pool keepalive (`keepalive_timeout` em ms, padrão 60000; `keepalive_pool`, padrão 30).
- Atalhos no módulo usam uma instância padrão: `HttpClient.get(url)`.
- Testes: `HttpClient.new({ factory = function() return fake end })`, em que `fake` implementa `set_timeouts`, `connect`, `request`, `set_keepalive` e `close`.

## E-mail — `crescent.mail`

SMTP sobre `lua-resty-mail` com STARTTLS.

```lua
local Mail = require("crescent.mail")

local mailer = Mail.new({
    server = "smtp.example.com", port = 587,
    user = "app@example.com", password = os.getenv("SMTP_PASSWORD"),
    from = "no-reply@example.com", from_name = "Minha App",
})

local ok, err = mailer:send({
    to = { "ada@example.com", { email = "grace@example.com", name = "Grace" } },
    cc = "time@example.com",
    bcc = { "auditoria@example.com" },
    reply_to = "suporte@example.com",
    subject = "Bem-vinda",
    text = "Olá!",
    html = "<p>Olá!</p>",
})
```

- Outros métodos: `send_text(to, subject, text)`, `send_html(to, subject, html, text)`, `send_template(to, subject, "emails/welcome.etlua", data)` (renderiza com `crescent.view` a partir de `views_root`, padrão `views`, e gera a versão texto), `verify()`.
- Retorno: `{ success = true, message, recipients }` ou `nil, err`.
- Campos ausentes vêm de `SMTP_SERVER`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD`, `SMTP_FROM`, `SMTP_FROM_NAME` (declare-os com `env` no `nginx.conf`).
- TLS: porta 465 usa TLS implícito (`ssl = true`); nas demais, `starttls = true` por padrão. `ssl_verify` ligado por padrão. Autenticação (`auth_type` `plain` ou `login`) só é usada quando há `user`.
- Segurança: endereços são validados; CR/LF/NUL em assunto, nomes, remetente e `reply_to` são rejeitados; textos não ASCII em headers usam RFC 2047.
- Testes: `Mail.new({ factory = function(options) return { send = function(self, message) ... end } end })`.
