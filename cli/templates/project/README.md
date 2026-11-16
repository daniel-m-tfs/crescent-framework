# {{project}}

Projeto [Crescent](https://crescent.tyne.com.br) — framework Lua sobre
**OpenResty** (Nginx + LuaJIT) com MySQL.

## Rodando com Docker (recomendado)

```bash
cp .env.example .env
docker compose up --build
```

- App: <http://127.0.0.1:8080> (hello world), `/api/hello?name=Ada`, `/health`, `/ready`
- MySQL: `127.0.0.1:3307` (usuário/senha do `.env`)
- O código é montado no container com recarga automática: edite e recarregue a página.
- As migrations pendentes rodam ao subir (`RUN_MIGRATIONS=true`).

Comandos dentro do container:

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
cp .env.example .env            # ajuste DB_HOST=127.0.0.1 e credenciais
./bin/crescent db:migrate
./bin/crescent server start     # http://127.0.0.1:8080
./test.sh
```

## Estrutura

```
app.lua                 monta a aplicação (middlewares + módulos)
config/                 configuração por ambiente (APP_ENV), lida do .env/ambiente
src/<módulo>/           init.lua (register), actions/, models/, services/, routes/
views/                  templates etlua (layout.etlua + páginas)
public/                 arquivos estáticos servidos pelo Nginx em /public/
migrations/  seeds/     bin/crescent make:migration | make:seeder
tests/                  bin/crescent test
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
