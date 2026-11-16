# Web: headers, cookies, sessões, CSRF e uploads

Módulos:

| Módulo | Função |
| --- | --- |
| `crescent.response` | `header`, `append_header`, `get_header`, `before_flush` |
| `crescent.cookie` | parse/serialização de cookies, cookies assinados |
| `crescent.session` / `crescent.middleware.session` | sessões em cookie criptografado ou `ngx.shared` |
| `crescent.middleware.csrf` | token sincronizador guardado na sessão |
| `crescent.upload` | `multipart/form-data` em streaming (`resty.upload`) |

## Chave secreta

Cookies assinados, sessões e CSRF usam `config.secret_key` (ou, se ausente, a
variável `APP_KEY`, já declarada com `env APP_KEY;` nos nginx.conf). Mínimo de
32 caracteres; gere com `openssl rand -base64 48`.

Rotação: mova a chave antiga para `secret_key_fallbacks` e coloque a nova em
`secret_key`. Valores novos são assinados/criptografados com a chave atual; os
antigos continuam válidos enquanto a chave antiga estiver na lista.

```lua
-- config/production.lua
secret_key = Env.get("APP_KEY"),
secret_key_fallbacks = { Env.get("APP_KEY_OLD") },  -- opcional, durante a rotação
```

## Headers da resposta

```lua
ctx.res:header("Cache-Control", "no-store")         -- define/substitui
ctx.res:append_header("Link", "</a.css>; rel=preload")  -- acumula (vira lista)
ctx.res:get_header("cache-control")                 -- nomes sem diferenciar maiúsculas
```

- `header(nome, nil)` remove o header. Nomes são case-insensitive: definir
  `content-type` substitui um `Content-Type` existente.
- `append_header` transforma valores repetidos em lista; o Nginx envia uma
  linha por item (ex.: vários `Set-Cookie`).
- Valores com CR/LF/NUL são recusados (erro → 500), inclusive em listas.

### `before_flush`

`ctx.res:before_flush(function(res) ... end)` registra um callback executado
**uma vez**, imediatamente antes de a resposta ser enviada (status e body já
definidos em `res.writer`). Serve para middleware que precisa escrever headers
depois da action — que normalmente envia a resposta antes de `next()`
retornar. O middleware de sessão usa isso para gravar o `Set-Cookie`. Se um
callback lançar erro, o envio é abortado e a aplicação responde 500 (o erro é
registrado no log).

## Cookies

```lua
ctx:cookie("theme")                     -- valor (percent-decoded) ou nil
ctx:cookies()                           -- tabela com todos

ctx:set_cookie("theme", "dark", {
    path = "/",            -- padrão "/"
    domain = nil,
    max_age = 3600,        -- segundos
    expires = os.time() + 3600,   -- epoch ou string HTTP-date
    http_only = true,      -- padrão true
    secure = nil,          -- padrão: true fora de debug
    same_site = "Lax",     -- "Strict" | "Lax" | "None" (None exige secure)
})
ctx:clear_cookie("theme", { path = "/" })   -- mesmo path/domain usado no set
```

- O header `Cookie` é lido uma vez por requisição; pares malformados são
  ignorados; se o nome repetir, vale o primeiro (o mais específico).
- Valores são percent-encoded ao gravar, então qualquer string faz round-trip.
- Nome, path, domain e expires com CR/LF/`;` ou nome fora do padrão de token
  geram erro (500), nunca header injetado.
- Chamar `set_cookie` duas vezes para o mesmo nome mantém só o último.

### Cookies assinados

```lua
ctx:set_cookie("uid", tostring(user.id), { signed = true })
local uid = ctx:signed_cookie("uid")    -- nil se ausente ou adulterado
```

O valor fica legível (`valor.assinatura`) mas não pode ser alterado: HMAC-SHA256
com a chave secreta, vinculado ao nome do cookie, comparado em tempo constante
e verificado contra `secret_key` e `secret_key_fallbacks`. Para conteúdo
secreto, use a sessão.

## Sessões

```lua
local session = require("crescent.middleware.session")

app:use(session.create({
    store = "cookie",             -- ou "shared"
    name = "crescent_session",
    max_age = 86400,              -- vida máxima absoluta (s); false desativa
    idle_timeout = 3600,          -- expira sem requisições (s); false desativa
    secret = nil,                 -- padrão: secret_key / APP_KEY
    secret_fallbacks = nil,       -- padrão: secret_key_fallbacks
    dict = "crescent_sessions",   -- store "shared"
    cookie = { path = "/", same_site = "Lax", http_only = true },  -- secure: padrão fora de debug
}))
```

`require("crescent.session").middleware(options)` é equivalente.

API em `ctx.session`:

| Método | Efeito |
| --- | --- |
| `get(k)` / `set(k, v)` / `delete(k)` | valores (precisam ser serializáveis em JSON) |
| `clear()` | remove todos os valores, mantém a sessão |
| `regenerate()` | novo id/novo cookie com os mesmos dados — **chame após login** e mudanças de privilégio (session fixation) |
| `destroy()` | apaga no servidor e expira o cookie; valores gravados depois iniciam uma sessão nova |
| `flash(k, v)` / `get_flash(k)` | valor disponível apenas na próxima requisição |
| `is_new()` | sessão criada nesta requisição |

```lua
app:post("/login", function(ctx)
    local user = authenticate(ctx.body.email, ctx.body.password)
    if not user then
        ctx.session:flash("error", "credenciais inválidas")
        return ctx:redirect("/login")
    end
    ctx.session:regenerate()
    ctx.session:set("user_id", user.id)
    return ctx:redirect("/")
end)

app:post("/logout", function(ctx)
    ctx.session:destroy()
    return ctx:redirect("/")
end)
```

- O `Set-Cookie` só é enviado quando a sessão mudou (ou em `regenerate`,
  `destroy`, renovação do idle timeout). Sessão nova sem dados não gera cookie.
- Cookie inválido, adulterado ou expirado é tratado como sessão nova e o
  cookie é expirado.
- O timer de inatividade é renovado no máximo a cada `min(60, idle_timeout/4)`
  segundos (`touch_interval`), para não regravar o cookie em toda requisição.

### Store `cookie`

Todo o conteúdo (JSON) vai no cookie, criptografado e autenticado com
AES-256-GCM; a chave é derivada do segredo com HKDF-SHA256 e o nome do cookie
entra como dado autenticado. Não precisa de estado no servidor, mas:

- Limite de **4096 bytes** do header: acima disso a requisição falha com 500 e
  o log explica (`session cookie is N bytes, above the 4096-byte browser
  limit...`). Guarde ids, não objetos.
- `destroy()` apaga o cookie do navegador, mas uma cópia roubada antes continua
  válida até expirar (`max_age`/`idle_timeout`). Se isso importa, use `shared`.

### Store `shared`

O cookie leva só um id aleatório de 128 bits (base64url) assinado; os dados
ficam em `lua_shared_dict crescent_sessions` (já declarado em `nginx.conf` e
`conf/nginx.production.conf`; o runner de testes e `bin/crescent` passam
`--shdict`), com TTL = `idle_timeout` (ou `max_age`). `destroy`/`regenerate`
removem o id antigo, então cópias roubadas deixam de valer. O dict é
compartilhado entre workers, mas é perdido em restart do Nginx e não é
compartilhado entre servidores: com vários servidores, use afinidade de sessão
ou o store `cookie`.

## CSRF

```lua
local session = require("crescent.middleware.session")
local csrf = require("crescent.middleware.csrf")

app:use(session.create())
app:use(csrf.create({
    skip = function(ctx) return ctx:get_bearer() ~= nil end,  -- APIs com bearer token
    safe_methods = { "GET", "HEAD", "OPTIONS", "TRACE" },     -- padrão
    field = "_csrf",                                          -- campo do formulário
    header = "X-CSRF-Token",                                  -- header (AJAX)
}))
```

- Requer o middleware de sessão **antes** dele; sem sessão, a requisição falha
  com 500 e a mensagem `CSRF protection requires the session middleware`.
- O token (256 bits) é criado na primeira chamada de `ctx:csrf_token()` e fica
  na sessão. Métodos não seguros precisam enviá-lo no campo `_csrf` (form
  urlencoded ou multipart) ou no header `X-CSRF-Token`; a comparação é em tempo
  constante. Falha → 403 `csrf_invalid`.
- `skip(ctx)` dispensa a verificação (ex.: APIs JSON autenticadas por bearer
  token, que não dependem de cookies do navegador).

Templates renderizados com `ctx:view` recebem `csrf_token()` e `csrf_field()`
quando há sessão. `csrf_field()` devolve HTML, então use `<%-` (sem escape):

```html
<form method="post" action="/posts">
  <%- csrf_field() %>
  ...
</form>
<meta name="csrf-token" content="<%= csrf_token() %>">
```

(`<%= csrf_field() %>` escaparia o HTML e mostraria a tag como texto.)

## Uploads (`multipart/form-data`)

Requisições `multipart/form-data` são lidas em streaming com `resty.upload`
(o body nunca é carregado inteiro na memória e `read_body` não é chamado):

- campos de texto vão para `ctx.body` (nomes repetidos viram listas, como no
  form urlencoded);
- arquivos são gravados em pedaços em arquivos temporários e expostos em
  `ctx.files[campo] = { filename, content_type, size, path, field }` (lista
  quando o campo se repete).

```lua
app:post("/avatar", function(ctx)
    local file = ctx.files.avatar
    if not file then return ctx:error(422, "avatar obrigatório", nil, "avatar_required") end
    if file.content_type ~= "image/png" then
        return ctx:error(422, "apenas PNG", nil, "invalid_type")
    end
    local path, err = ctx:save_upload(file, "avatars/" .. ctx.state.user.id .. ".png", { overwrite = true })
    if not path then return ctx:error(500, "falha ao salvar", nil, "upload_failed") end
    return ctx:json(201, { path = path })
end)
```

Configuração (na config da aplicação):

```lua
upload_dir = "tmp/uploads",          -- temporários; relativo ao prefixo do OpenResty; criado se preciso
upload_root = "storage",             -- única árvore em que save_upload grava
upload = {
    max_file_size = 10 * 1024 * 1024, -- por arquivo
    max_files = 10,
    max_fields = 100,
    max_field_size = 64 * 1024,       -- por campo de texto
    max_total_size = 50 * 1024 * 1024,
    chunk_size = 8192,
    timeout = nil,                    -- ms por leitura do socket (padrão do lua_socket)
},
```

Erros (os arquivos temporários já gravados são apagados):

| Situação | Status | `code` |
| --- | --- | --- |
| arquivo, campo ou total acima do limite | 413 | `upload_too_large` |
| arquivos demais | 413 | `too_many_files` |
| campos demais | 413 | `too_many_fields` |
| body inválido, sem boundary, conexão interrompida | 400 | `malformed_multipart` |
| diretório temporário sem permissão | 500 | `upload_unavailable` |

Segurança:

- `filename` é sanitizado (só o basename, sem caracteres de controle nem pontos
  iniciais) mas continua sendo dado do cliente: não confie nele nem em
  `content_type` — valide o conteúdo e prefira gerar o nome final.
- Os temporários são apagados ao fim da requisição, a menos que a action chame
  `ctx:save_upload(file, destino, { overwrite = false })`. O destino é relativo
  a `upload_root` (ou absoluto dentro dele); `..`, `.` e caminhos fora da raiz
  são recusados, assim como sobrescrever sem `overwrite = true`. Retorna o
  caminho final ou `nil, mensagem`. Diretórios intermediários são criados.
  Links simbólicos dentro da raiz não são resolvidos: não crie links para fora
  dela.
- O body é lido antes do middleware (como JSON/form), então qualquer cliente
  pode enviar até os limites configurados. Ajuste `client_max_body_size` no
  nginx.conf de acordo e aplique rate limit às rotas de upload.
