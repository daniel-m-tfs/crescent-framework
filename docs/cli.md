# CLI do Crescent

Rode da raiz do projeto:

```bash
lua cli.lua <comando> [argumentos]
lua cli.lua help
```

Geradores, `new`, `server` e `test` rodam no Lua comum (5.1–5.4 ou LuaJIT).
`routes` e `db:*` precisam do OpenResty: no Lua comum, `cli.lua` os repassa
para `bin/crescent`, que localiza o `resty` (sobrescreva com `RESTY_BIN`), entra
na raiz do projeto e executa `cli.lua` com `lua_modules/` no `package.path`.
`./bin/crescent <comando>` aceita os mesmos comandos (é o que se usa no Docker).

A CLI lê o `.env` da raiz do projeto (variáveis do processo têm prioridade).
A saída usa cores e ícones (`🌙` cabeçalhos, `✓` criado/sucesso, `✗` erro,
`ℹ` próximos passos, `⚠` aviso) quando o stdout é um terminal; `NO_COLOR=1`
desliga as cores e `CRESCENT_COLOR=1` força.

## Estrutura de um módulo

```
src/<módulo>/
  init.lua            Module.register(app)
  controllers/        recebem ctx, chamam services e respondem (ctx:json, ctx:view, ctx:error)
  services/           regras de negócio, sem ctx; recebem o adaptador de banco
  models/             Model:extend({ table, fillable, hidden, timestamps, validates })
  routes/             function(app, prefix) com rotas nomeadas
```

## Projeto

| Comando | Descrição |
| --- | --- |
| `new <nome>` | Cria `./<nome>` a partir de `cli/templates/project/` (sem rede) e uma cópia de `crescent/`, `cli/`, `cli.lua`, `bin/`, configs do Nginx/Docker e `deps.sh`. Cria o `.env` com `APP_KEY` e `JWT_SECRET` aleatórios (o `.env.example` mantém os segredos vazios). Recusa diretórios existentes. |
| `server [start\|stop\|reload\|status]` | Controla `openresty -p <raiz>/ -c nginx.conf`. Opções: `--conf <arquivo>` (ex.: `conf/nginx.production.conf`) e `--env <nome>` (define `APP_ENV`). `stop` é gracioso (`-s quit`). Binário: `OPENRESTY_BIN`. |
| `routes` | Carrega `app.lua` e lista `METHOD  PATH  NAME`. |

Depois de `new`:

```bash
cd meu-app
lua cli.lua setup              # git, credenciais do banco e Docker com hot reload
# ou, sem Docker:
./deps.sh && lua cli.lua server start
```

## Desenvolvimento com Docker

| Comando | Descrição |
| --- | --- |
| `setup` | Prepara o projeto, perguntando antes de cada passo: (1) **git** — recomeça o histórico do zero (`git init`, branch `main`, commit inicial) sem o remote do template e, opcionalmente, adiciona o seu remote e faz o push; (2) **banco** — usuário e senha do MySQL do Docker gravados no `.env` (senha vazia = gerada; `DB_ROOT_PASSWORD` aleatória); (3) **cache e filas** — memória do servidor (`shared`) ou Redis (`COMPOSE_PROFILES=redis`, `CACHE_DRIVER`/`QUEUE_DRIVER=redis`, `REDIS_PASSWORD` aleatória), veja [cache-queue.md](cache-queue.md); (4) **Docker** — sobe a aplicação com `run`. |
| `run [--logs]` | `docker compose up -d`, espera o `/health` responder e mostra as URLs. O código fica montado no container com `lua_code_cache off`: alterações em `src/`, `views/` e `app.lua` valem na próxima requisição. `--logs` acompanha os logs da aplicação. |
| `rerun [--logs] [--fresh]` | Reconstrói a imagem e reinicia (`up -d --build`, com cache): use depois de mudar `Dockerfile`, dependências (`deps.sh`) ou configuração do Nginx. `--fresh` reconstrói sem cache. |
| `stop` | `docker compose down` (inclusive `redis`/`worker`): para os containers e mantém os volumes (banco, Redis e uploads). |

Se o volume do MySQL já existe, o `setup` avisa: o MySQL só lê usuário e senha ao criar o volume (`docker compose down -v` recria, apagando os dados do banco do Docker). O `setup` se recusa a rodar no repositório do próprio framework.

## Geradores

Nomes aceitos: `^[%a][%w_%-]*$` (até 64 caracteres). Nomes são validados antes
de qualquer acesso ao disco e nunca são interpolados em comandos de shell.
Arquivos existentes **nunca** são sobrescritos. `BlogPost` e `blog-post` viram
`blog_post` em arquivos e `BlogPost` em identificadores; o módulo padrão é o
próprio nome.

| Comando | Gera |
| --- | --- |
| `make:module <nome>` | Módulo CRUD completo (estrutura acima), `tests/test-<m>-module.lua` e a migration `create_<plural>_table` |
| `make:controller <nome> [módulo]` | `src/<módulo>/controllers/<nome>.lua` (`make:action` é alias, nome usado no 2.0.0) |
| `make:service <nome> [módulo]` | `src/<módulo>/services/<nome>.lua` |
| `make:model <nome> [módulo]` | `src/<módulo>/models/<nome>.lua` |
| `make:routes <nome> [módulo]` | `src/<módulo>/routes/<nome>.lua` |
| `make:middleware <nome> [módulo]` | `src/middleware/<nome>.lua` (ou dentro do módulo), no formato `function(ctx, next) return next() end` |
| `make:job <nome> [módulo]` | `src/<módulo>/jobs/<nome>.lua`, job de fila com `handle(payload, job)` e `failed` |
| `make:test <nome>` | `tests/test-<nome>.lua` |
| `make:migration <nome>` | `migrations/AAAAMMDDHHMMSS_<nome>.lua`. `create_<t>[_table]` gera `CREATE TABLE <t>`; `add_x_to_<t>`, `remove_x_from_<t>`, `alter_<t>_table` geram um `ALTER TABLE <t>` |
| `make:seeder <nome>` | `seeds/<nome>.lua`; pode começar com número (`01_admin_user`) para ordenar |

### Módulo CRUD

`lua cli.lua make:module Product` cria rotas nomeadas:

| Método | Caminho | Nome | Resultado |
| --- | --- | --- | --- |
| GET | `/products` | `products.index` | lista paginada (`?page=&per_page=`) |
| GET | `/products/{id}` | `products.show` | 200 ou 404 |
| POST | `/products` | `products.store` | `app:validated(schema, ...)`, 201 ou 422 |
| PUT | `/products/{id}` | `products.update` | 200, 404 ou 422 |
| DELETE | `/products/{id}` | `products.destroy` | 204 ou 404 |

Registre em `app.lua`: `require("src.product").register(app)`.

O controller usa o adaptador de banco em `ctx.db`; sem ele responde
`503 database_unavailable`. O service recebe o adaptador como primeiro
argumento e usa o model.

## Banco (MySQL)

| Comando | Alias | Descrição |
| --- | --- | --- |
| `db:migrate` | `migrate` | aplica as pendentes |
| `db:rollback` | `migrate:rollback` | desfaz o último lote (batch) |
| `db:status` | `migrate:status` | `ran`, `pending` ou `missing`, com o lote |
| `db:seed [nome]` | — | todos os seeders em ordem de nome, ou só um |

## Filas e cache

Rodam no OpenResty (`bin/crescent`) e carregam o `app.lua`. Os comandos de fila
exigem `QUEUE_DRIVER=redis`; detalhes em [cache-queue.md](cache-queue.md).

| Comando | Descrição |
| --- | --- |
| `queue:work [--queue=a,b] [--once]` | processa jobs (`--sleep`, `--max-jobs`, `--max-time`, `--stop-when-empty`); logs JSON no stdout |
| `queue:status [fila]` | contagem de ready, delayed, reserved e failed |
| `queue:failed [fila]` | últimos jobs que falharam (`--limit=20`) |
| `queue:retry <id\|all> [--queue=]` | reenfileira jobs que falharam, com tentativas zeradas |
| `queue:clear-failed [fila]` | apaga os jobs que falharam |
| `cache:clear` | apaga as chaves do prefixo do cache (Redis) |

## Testes

| Comando | Descrição |
| --- | --- |
| `test [filtro]` | Executa `tests/test*.lua` com `resty`; mostra `✓`/`✗` por teste e um resumo (arquivos, testes, tempo, arquivos que falharam) |
| `test:http` | Executa `tests/test-http.sh` contra um OpenResty real (projetos novos trazem um smoke test de `/health`, `/` e `/api/hello`) |

Códigos de saída: `0` sucesso, `1` falha do comando, `2` comando desconhecido.
