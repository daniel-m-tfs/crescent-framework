# Crescent Framework

Framework web em **Lua sobre OpenResty** (Nginx + LuaJIT), com MySQL. O OpenResty/Nginx cuida do
HTTP (TLS, workers, keep-alive, limites, arquivos estáticos); o framework cuida
de rotas, controllers, middleware, validação, erros, ORM/MySQL, templates, segurança
e CLI.

## Requisitos

- OpenResty (LuaJIT) — inclui `lua-resty-mysql`, `lua-resty-openssl`, `lua-resty-limit-traffic`
- LuaRocks — dependências puras em `lua_modules/` (`etlua`, `lua-resty-http`, `lua-resty-mail`)
- MySQL/MariaDB

## Início rápido

```bash
lua cli.lua new meu-app        # projeto novo, já com .env e segredos aleatórios
cd meu-app
./deps.sh                      # instala dependências em ./lua_modules
lua cli.lua server start       # openresty -p . -c nginx.conf (porta 8080)
curl http://127.0.0.1:8080/health   # liveness; /ready verifica o banco
lua cli.lua make:module Product
lua cli.lua db:migrate
```

Em produção use `conf/nginx.production.conf` (revise antes):
`APP_ENV=production openresty -p /srv/app/ -c conf/nginx.production.conf`.

## Como funciona

- `app.lua` monta a aplicação **uma vez por worker**; o Nginx chama
  `require("app"):run()` a cada requisição (`content_by_lua_block`).
- Configuração por ambiente em `config/<APP_ENV>.lua`, lida via
  `crescent.env` (variável do processo > `.env` > padrão). **Toda variável
  usada precisa de uma diretiva `env NOME;` no nginx.conf** — o Nginx limpa o
  ambiente dos workers.
- Módulos em `src/<módulo>/{controllers,services,models,routes}` com
  `init.lua` (`register(app)`). Controllers recebem `ctx` e respondem com `ctx:json`, `ctx:text`, `ctx:html`,
  `ctx:view`, `ctx:redirect`, `ctx:no_content` ou `ctx:error(status, msg,
  detalhes, codigo)`. Retornar uma tabela/string envia 200 JSON/texto.
- Middleware: `app:use(function(ctx, next) ... return next() end)`; para
  bloquear, retorne uma resposta sem chamar `next()`.
- Rotas: `/users/{id}`, opcionais `/{id?}`, wildcard `/{path*}`, grupos
  `app:group("/api", fn)`, nomes `app:get(path, action, "users.show")`.
  HEAD usa a rota GET; 405 inclui `Allow`.
- Erros têm `code` estável; detalhes internos só com `debug = true`. Todo 500 é
  registrado no error log com o request id. Erros com `status` 4xx (ex.:
  `Model:find_or_fail`) viram a resposta correspondente.
- `X-Request-Id`: preserva o do proxy, senão usa `$request_id` do Nginx.
- Bodies JSON e form são decodificados em `ctx.body` (`ctx.raw_body` mantém o
  texto); bodies gravados em disco pelo Nginx também são lidos.

## Documentação

| Tema | Arquivo |
|---|---|
| Banco, Query Builder, ORM, migrations | [docs/database.md](docs/database.md) |
| JWT, senhas, auth, CORS, headers, rate limit | [docs/security.md](docs/security.md) |
| Cookies, sessões, CSRF, uploads multipart | [docs/web.md](docs/web.md) |
| CLI (`new`, `make:*`, `server`, `routes`, `db:*`) | [docs/cli.md](docs/cli.md) |
| HTTP client e e-mail | [docs/integrations.md](docs/integrations.md) |
| Logs estruturados, health/readiness | [docs/observability.md](docs/observability.md) |

## Testes

```bash
./test.sh                  # unitários (no LuaJIT do OpenResty via resty) + HTTP real
lua cli.lua test jwt       # filtra por nome de arquivo
```

Os testes de integração MySQL são pulados sem credenciais. Para rodá-los,
use um usuário com acesso apenas ao banco de teste:

```bash
DB_USER=... DB_PASSWORD=... DB_HOST=127.0.0.1 DB_PORT=3306 \
DB_TEST_NAME=crescent_test lua cli.lua test mysql-integration
```

## Migração a partir do Crescent 1.x (Luvit)

- `ctx.json(...)` → `ctx:json(...)` (dois-pontos em todo o contexto).
- Middleware: `return false` para interromper → retornar uma resposta sem `next()`.
- Opções de JWT em snake_case (`expires_in`, `not_before`).
- Hashes de senha do Crescent antigo (`iter$salt$hash`) continuam válidos.
- `crescent.utils.http` → `crescent.http_client`; `crescent.utils.mail` → `crescent.mail`.
- Arquivos estáticos: sirva pelo Nginx (`location /public/`), não por middleware.

## Começando um projeto

Use o template [crescent-starter](https://github.com/daniel-m-tfs/crescent-starter)
(hello world + Docker) ou gere um projeto a partir deste repositório:

```bash
./bin/crescent new meu-projeto
```

Documentação completa: <https://crescent.tyne.com.br>.

## Licença

MIT — veja [LICENSE](LICENSE).
