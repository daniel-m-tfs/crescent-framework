# {{project}}

Projeto [Crescent](https://crescent.tyne.com.br) — framework Lua sobre
**OpenResty** (Nginx + LuaJIT) com MySQL.

## Rodando com Docker (recomendado)

```bash
lua cli.lua setup     # git do zero (+ remote opcional), usuário/senha do MySQL e sobe o Docker
lua cli.lua run       # dia a dia: sobe app + MySQL com hot reload (--logs acompanha os logs)
lua cli.lua rerun     # reconstrói a imagem (Dockerfile, dependências, Nginx) e reinicia
lua cli.lua stop      # para os containers; banco e uploads ficam nos volumes
```

- App: <http://127.0.0.1:8080> (hello world), `/api/hello?name=Ada`, `/health`, `/ready`
- MySQL: `127.0.0.1:3307` (usuário/senha do `.env`)
- O código é montado no container com recarga automática: edite e recarregue a página.
- As migrations pendentes rodam ao subir (`RUN_MIGRATIONS=true`).

Comandos dentro do container (`bin/crescent` aceita os mesmos comandos de `lua cli.lua`):

```bash
docker compose exec app bin/crescent make:module Product
docker compose exec app bin/crescent db:migrate
docker compose exec app bin/crescent test
docker compose exec app bin/crescent routes
```

## Rodando sem Docker

Requer OpenResty, LuaRocks e MySQL instalados.

```bash
./deps.sh                       # etlua, lua-resty-http, lua-resty-mail em ./lua_modules
# ajuste DB_HOST=127.0.0.1 e as credenciais no .env
lua cli.lua db:migrate
lua cli.lua server start        # http://127.0.0.1:8080
./test.sh                       # lua cli.lua test + lua cli.lua test:http
```

## CLI

```bash
lua cli.lua help                       # lista todos os comandos
lua cli.lua make:module Product        # CRUD completo + teste + migration
lua cli.lua make:controller Report shop
lua cli.lua make:migration add_price_to_products
lua cli.lua db:migrate                 # db:rollback, db:status, db:seed
lua cli.lua test                       # ou: lua cli.lua test products
```

Geradores, `test` e `server` rodam no Lua comum; comandos de banco e
`routes` são repassados para `bin/crescent` (OpenResty/`resty`).

## Desenvolvendo com IA

O [`llm.md`](llm.md) descreve a estrutura, as convenções e a API do Crescent
para modelos de IA (Claude, ChatGPT, Copilot, Cursor...). Peça para o assistente
ler esse arquivo antes de gerar código, ou aponte para ele no arquivo de
instruções da ferramenta (`CLAUDE.md`, `AGENTS.md`, `.cursorrules`).

## Estrutura

```
app.lua                 monta a aplicação (middlewares + módulos)
config/                 configuração por ambiente (APP_ENV), lida do .env/ambiente
src/<módulo>/           init.lua (register), controllers/, services/, models/, routes/
views/                  templates etlua (layout.etlua + páginas)
public/                 arquivos estáticos servidos pelo Nginx em /public/
migrations/  seeds/     lua cli.lua make:migration | make:seeder
storage/                uploads (upload_root = "storage")
tests/                  lua cli.lua test
llm.md                  guia do framework para modelos de IA
crescent/  cli/         o framework (versionado junto com o projeto)
nginx.conf              desenvolvimento local
conf/                   nginx de produção e dos containers
docker/  Dockerfile  docker-compose.yml
```

## Produção

A imagem (`docker build -t {{project}} .`) usa `conf/nginx.docker.conf`
(cache de código ligado, logs JSON em stdout). Defina no ambiente:
`APP_ENV=production`, `DB_*`, `APP_KEY` e `JWT_SECRET` (32+ bytes:
`openssl rand -base64 48`). Use `RUN_MIGRATIONS=true` ou rode
`bin/crescent db:migrate` no deploy. Toda variável lida pela aplicação
precisa de uma diretiva `env NOME;` nos arquivos de `conf/`.

Documentação: <https://crescent.tyne.com.br> · código do framework:
<https://github.com/daniel-m-tfs/crescent-framework>.
