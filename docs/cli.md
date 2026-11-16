# CLI do Crescent

A CLI roda no mesmo runtime que atende as requisições (LuaJIT do OpenResty):

```bash
./bin/crescent <comando> [argumentos]
```

`bin/crescent` localiza o `resty` (sobrescreva com `RESTY_BIN`), entra na raiz do
projeto e executa `cli.lua` com `lua_modules/` no `package.path`. Os comandos
`test` e `help` também funcionam com Lua puro (`lua cli.lua test`, usado pelo
`test.sh`); `routes` e `db:*` exigem o OpenResty.

## Projeto

| Comando | Descrição |
| --- | --- |
| `new <nome>` | Cria `./<nome>` a partir de `cli/templates/project/` (sem rede): `app.lua`, `nginx.conf`, `conf/nginx.production.conf`, `config/*.lua`, `.env.example`, `.gitignore`, `deps.sh`, `test.sh`, módulo `src/health`, `tests/` e uma cópia de `crescent/`, `cli/`, `cli.lua` e `bin/`. Recusa diretórios existentes. |
| `server [start\|stop\|reload\|status]` | Controla `openresty -p <raiz>/ -c nginx.conf`. Opções: `--conf <arquivo>` (ex.: `conf/nginx.production.conf`) e `--env <nome>` (define `APP_ENV`; sem a opção o `APP_ENV` atual é repassado). `stop` é gracioso (`-s quit`). Binário: `OPENRESTY_BIN`. |
| `routes` | Carrega `app.lua` e lista `METHOD  PATH  NAME`. |

Depois de `new`:

```bash
cd meu-app
./deps.sh
cp .env.example .env
./bin/crescent server start
curl http://127.0.0.1:8080/health
```

## Geradores

Nomes aceitos: `^[%a][%w_%-]*$` (até 64 caracteres). Nomes são validados antes
de qualquer acesso ao disco e nunca são interpolados em comandos de shell.
Arquivos existentes **nunca** são sobrescritos. `BlogPost` e `blog-post` viram
`blog_post` em arquivos e `BlogPost` em identificadores; o módulo padrão é o
próprio nome.

| Comando | Gera |
| --- | --- |
| `make:module <nome>` | Módulo CRUD completo: `src/<m>/init.lua` (`register(app)`), `models/`, `services/`, `actions/`, `routes/` e `tests/test-<m>-module.lua` |
| `make:action <nome> [módulo]` | `src/<módulo>/actions/<nome>.lua` |
| `make:service <nome> [módulo]` | `src/<módulo>/services/<nome>.lua` |
| `make:model <nome> [módulo]` | `src/<módulo>/models/<nome>.lua` (`Model:extend{ table, fillable, hidden, timestamps, validates }`) |
| `make:routes <nome> [módulo]` | `src/<módulo>/routes/<nome>.lua` |
| `make:middleware <nome> [módulo]` | `src/middleware/<nome>.lua` (ou dentro do módulo), no formato `function(ctx, next) return next() end` |
| `make:test <nome>` | `tests/test-<nome>.lua` |
| `make:migration <nome>` | `migrations/AAAAMMDDHHMMSS_<nome>.lua` retornando `{ up = function() return "SQL" end, down = ... }`; delega para `cli.commands.db.make_migration` quando existir |

### Módulo CRUD

`./bin/crescent make:module Product` cria rotas nomeadas:

| Método | Caminho | Nome | Ação |
| --- | --- | --- | --- |
| GET | `/products` | `products.index` | lista |
| GET | `/products/{id}` | `products.show` | 200 ou 404 |
| POST | `/products` | `products.store` | `app:validated(schema, ...)`, 201 ou 422 |
| PUT | `/products/{id}` | `products.update` | 200, 404 ou 422 |
| DELETE | `/products/{id}` | `products.destroy` | 204 ou 404 |

Registre em `app.lua`: `require("src.product").register(app)`.

As ações usam o adaptador de banco em `ctx.db` (ou `app.db`); sem ele
respondem `503 database_unavailable`. O service recebe o adaptador como primeiro
argumento e usa `crescent.database.query_builder` + o model.

## Banco (MySQL)

| Comando | Alias |
| --- | --- |
| `db:migrate` | `migrate` |
| `db:rollback` | `migrate:rollback` |
| `db:status` | `migrate:status` |

Implementados em `cli/commands/db.lua`; se o arquivo não existir a CLI avisa e
sai com código 1.

## Testes

| Comando | Descrição |
| --- | --- |
| `test [filtro]` | Executa `tests/test*.lua` com `resty` |
| `test:http` | Testes de integração HTTP contra o OpenResty |

Códigos de saída: `0` sucesso, `1` falha do comando, `2` comando desconhecido.
