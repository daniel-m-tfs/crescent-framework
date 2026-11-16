# Banco de dados

A camada de dados do Crescent roda sobre `lua-resty-mysql` (cosockets do
OpenResty). Por enquanto **somente MySQL/MariaDB** é suportado.

Módulos:

| Módulo | Papel |
| --- | --- |
| `crescent.database` | Gerenciador global (`configure`, `default`, `transaction`) |
| `crescent.database.mysql` | Adapter MySQL (pool, bindings, transações) |
| `crescent.database.query_builder` | Query builder (SQL e bindings separados) |
| `crescent.database.migration` | Migrations com tabela `migrations` persistente |
| `crescent.model` | ORM Active Record (validação, soft delete, relações) |
| `cli.commands.db` | Comandos `migrate`, `rollback`, `status`, `make_migration` |

## Configuração

Configure uma vez no boot da aplicação, a partir de `config.database`:

```lua
local Database = require("crescent.database")
Database.configure(config.database)
```

Chaves aceitas (além de `host`, `port`, `database`, `user`, `password`):

| Chave | Padrão | Descrição |
| --- | --- | --- |
| `charset` | `"utf8mb4"` | charset da conexão |
| `connect_timeout` | `5000` | timeout de conexão (ms) |
| `timeout` | `10000` | timeout de leitura/escrita (ms) |
| `max_idle_timeout` | `10000` | tempo ocioso no pool (`set_keepalive`, ms) |
| `pool_size` | `100` | conexões mantidas no pool por worker |
| `keepalive` | `true` | `false` fecha a conexão após cada query |
| `pool_name`, `ssl`, `ssl_verify`, `path`, `max_packet_size` | — | repassados ao `resty.mysql` |

`Database.default()` devolve o adapter; models e query builder o usam quando
nenhum adapter é passado. Em testes, `Database.set_default(fake)` injeta
qualquer objeto com `query`/`execute`, e `Database.configure(cfg, { driver = fake_resty_mysql })`
troca o driver.

## Adapter e bindings

```lua
local db = Database.default()
local rows, err = db:query("SELECT * FROM users WHERE email = ?", { email })
local result = db:execute("UPDATE users SET name = ? WHERE id = ?", { "Ada", 1 })
-- result = { affected_rows = 1, insert_id = 0 }
```

- `lua-resty-mysql` usa o protocolo texto: cada `?` é substituído pelo valor
  escapado com `ngx.quote_sql_str`. `?` dentro de strings, identificadores com
  crase e comentários é ignorado; a quantidade de bindings é validada.
- `nil`/`Database.NULL` → `NULL`, booleanos → `1`/`0`; NaN/infinito e tabelas
  são rejeitados. Para `nil` no meio da lista use `{ n = 3, a, nil, c }`.
- SELECT devolve um array de linhas (`NULL` vira `nil`); escritas devolvem
  `{ affected_rows, insert_id }`.
- Erros: `nil, err, errno, sqlstate, kind`. `kind` é `"unique_violation"`
  (errno 1062), `"foreign_key_violation"`, `"deadlock"`, `"lock_timeout"`,
  `"connection"`, `"bind"` ou `"query"`.
- Cada query pega uma conexão do pool e a devolve com `set_keepalive`. Conexões
  com erro de rede ou com transação aberta são fechadas, nunca devolvidas.

### Transações

```lua
local user, err = Database.transaction(function(tx)
    local user = assert(User:create({ name = "Ada", email = "ada@x.io" }, tx))
    tx:execute("INSERT INTO audit (user_id) VALUES (?)", { user.id })
    return user
end)
```

Uma única conexão fica presa durante `fn(tx)`. `COMMIT` se a função retornar
normalmente; `ROLLBACK` se ela lançar erro, retornar `false` ou `nil, err`.
`tx:transaction(fn)` aninhado usa `SAVEPOINT`. Passe `tx` como adapter para
models e query builder dentro da transação.

## Query builder

```lua
local QueryBuilder = require("crescent.database.query_builder")

local rows = QueryBuilder.table("users")
    :select("id", "name")
    :where("active", true)
    :where(function(q) q:where("age", ">=", 18):or_where("verified", true) end)
    :where_in("role", { "admin", "editor" })
    :left_join("profiles", "profiles.user_id", "users.id")
    :order_by("created_at", "DESC")
    :paginate(2, 20)
    :get()
```

- Filtros: `where`, `or_where`, `where_null`, `where_not_null`, `or_where_null`,
  `where_in`, `or_where_in`, `where_not_in`, `where_raw(sql, bindings)`; grupos
  com `where(function(q) ... end)`. `where(col, nil)` gera `IS NULL`.
- `join`/`left_join`/`right_join`, `order_by`, `limit`/`take`, `offset`/`skip`,
  `paginate(page, per_page)`.
- Execução: `get()`, `first()`, `count()`, `exists()`, `insert(values)` (aceita
  lista de linhas), `update(values)`, `delete()`. Todos aceitam um adapter
  opcional (`get(tx)`, `insert(tx, values)`) ou `:using(adapter)`; senão usam
  `Database.default()`.
- `update`/`delete` sem `WHERE` lançam erro.
- `to_sql()`, `to_count_sql()`, `to_insert()`, `to_update()`, `to_delete()`
  devolvem `sql, bindings` sem executar.
- `QueryBuilder.raw(sql, bindings[, adapter])` para SQL livre (sempre com `?`).
- Identificadores são validados (`^[%a_][%w_]*$`, com `tabela.coluna`) e
  operadores vêm de uma allowlist.
- Aliases camelCase: `orWhere`, `whereNull`, `whereNotNull`, `whereIn`,
  `whereNotIn`, `leftJoin`, `orderBy`, `toSql`...

## Models

```lua
local Model = require("crescent.model")

local User = Model:extend({
    table = "users",
    fillable = { "name", "email", "password" },
    hidden = { "password" },
    timestamps = true,      -- created_at / updated_at
    soft_deletes = true,    -- deleted_at
    validates = {
        name = { required = true, min_length = 3 },
        email = { required = true, email = true, unique = true },
    },
    relations = {
        posts = { type = "has_many", model = "src.blog.models.post" },
        profile = { type = "has_one", model = "src.users.models.profile" },
    },
    before_save = function(user) user.email = user.email:lower() end,
})
```

Classe: `User:find(id)`, `User:find_or_fail(id)` (lança erro com `status = 404`,
ver `Model.is_not_found(err)`), `User:first()`, `User:all()`, `User:count()`,
`User:where(...)`, `User:query()`, `User:with(...)`, `User:with_trashed()`,
`User:only_trashed()`, `User:create(attrs)`, `User:raw(sql, bindings)`,
`User:hydrate(row)`. O último argumento opcional de todos é o adapter.

Instância: `get/set`, `fill`, `save()`, `update(attrs)`, `delete()`,
`force_delete()`, `restore()`, `trashed()`, `is_dirty(col)`, `get_dirty()`,
`load("posts")`, `relation("posts")`, `to_table()`. `user.name` também lê o
atributo — exceto quando o nome colide com um método/campo da classe (`table`,
`save`, `update`...); nesse caso use `user:get("coluna")`.

Regras:

- `new`/`fill`/`update` respeitam `fillable`/`guarded`; linhas vindas do banco
  (`hydrate`) ignoram `fillable` e têm `exists = true`.
- `save` faz INSERT ou UPDATE apenas das colunas alteradas (comparadas com
  `original`); a chave primária nunca é escrita no UPDATE.
- `create`/`save`/`update` devolvem o model, ou `nil, errors` (validação via
  `crescent.validation` + `unique`). Uma violação de chave única do MySQL vira
  `errors[campo] = { { code = "unique", ... } }` (ou `errors._database`).
- Hooks: `before_save`, `before_create`/`before_update`, `after_create`/`after_update`,
  `after_save`, `before_delete`, `after_delete`. Um `before_*` que retorna
  `false` aborta a operação.
- Soft delete: `delete()` grava `deleted_at`; as consultas excluem linhas
  apagadas, salvo `with_trashed()`/`only_trashed()`. `query():delete()` em massa
  também vira UPDATE; `force_delete()` apaga de fato.

### Tipos das colunas (`casts`)

O `lua-resty-mysql` devolve colunas `BIGINT` como string (podem passar de
2^53). Ao carregar um registro, a chave primária e as colunas `*_id` com um
inteiro canônico de até 15 dígitos viram número — o `id` tem o mesmo tipo
depois de um INSERT e de um SELECT. Para outras colunas, ou para manter uma
`*_id` textual, declare `casts`:

```lua
local Product = Model:extend({
    table = "products",
    casts = { external_id = "string", active = "boolean", price = "number" },
})
```

Casts disponíveis: `string`, `number`, `integer`, `boolean` (`1`/`0` → `true`/`false`).

### Paginação

```lua
local page = Product:page(ctx.query.page, ctx.query.per_page)
-- page.data = { models }, page.meta = { page, per_page, total, last_page, from, to }
Product:where("active", 1):order_by("name"):page(2, 20)
```

Valores inválidos de `page`/`per_page` caem no padrão (1 e 15) e `per_page`
é limitado a 100 (`{ max_per_page = n }` no terceiro argumento).

### Relações

Um único estilo: a tabela `relations` na definição.

| Tipo | Chaves (padrões) |
| --- | --- |
| `has_many` / `has_one` | `foreign_key` = singular(tabela do pai) .. `_id`, `local_key` = PK do pai |
| `belongs_to` | `foreign_key` = singular(tabela relacionada) .. `_id`, `owner_key` = PK relacionada |

`model` pode ser o próprio model, o nome do módulo (resolvido com `require`,
evita dependência circular) ou uma função que devolve o model. A
singularização é heurística (`categories` → `category`, `addresses` →
`address`, `people` → `person`); informe `foreign_key` quando não servir.

Eager loading — uma query `WHERE fk IN (...)` por relação, sem N+1:

```lua
local users = User:query()
    :with("posts.comments", { profile = function(q) q:select("id", "user_id", "bio") end })
    :get()
users[1].posts          -- array de Post
users[1]:to_table()     -- inclui relações carregadas
```

Restrições como `limit` na função de relação valem para a query inteira, não
por pai. `user:get("posts")` carrega a relação sob demanda na primeira vez.

## Migrations

Arquivos em `migrations/AAAAMMDDHHMMSS_nome.lua`, executados em ordem de nome:

```lua
return {
    up = function(db)
        return {
            "CREATE TABLE `users` (`id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `email` VARCHAR(191) NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
            "CREATE UNIQUE INDEX `users_email` ON `users` (`email`)",
        }
    end,
    down = function(db) return "DROP TABLE `users`" end,
}
```

`up`/`down` devolvem uma string SQL, uma lista, `{ sql = ..., bindings = ... }`
ou `{}` (no-op). A tabela `migrations` (`id`, `migration`, `batch`,
`executed_at`; InnoDB utf8mb4) é criada se não existir.

```lua
local Migrator = require("crescent.database.migration")
local runner = Migrator.new()          -- usa Database.default() e ./migrations
runner:migrate()   -- { batch = 3, migrated = { ... } } ou nil, err, info
runner:rollback()  -- reverte o último batch em ordem inversa
runner:status()    -- { { name, ran, batch, executed_at }, ... }
```

**Atenção:** DDL do MySQL faz commit implícito, então migrations não rodam em
transação. Cada migration é registrada logo após seu SQL ter sucesso e o batch
para na primeira falha. Se uma migration com vários comandos falhar no meio,
ela fica parcialmente aplicada e sem registro — prefira um comando de schema
por migration e corrija manualmente antes de rodar de novo.

CLI (precisa do `resty`, por causa dos cosockets):

```sh
resty -I lua_modules/share/lua/5.1 cli/commands/db.lua migrate
resty -I lua_modules/share/lua/5.1 cli/commands/db.lua rollback
resty -I lua_modules/share/lua/5.1 cli/commands/db.lua status
resty -I lua_modules/share/lua/5.1 cli/commands/db.lua make_migration create_users
```

Os comandos carregam `crescent.config` (`APP_ENV`) e chamam
`Database.configure(config.database)`. O nome da migration deve casar com
`^[%a][%w_]*$`.

## Seeders

```bash
bin/crescent make:seeder 01_admin_user   # cria seeds/01_admin_user.lua
bin/crescent db:seed                     # roda todos, em ordem de nome
bin/crescent db:seed 01_admin_user       # só um
```

Cada seeder é `return function(db) ... end` e roda na sua própria transação
(erro ou `return false` desfaz). Não há registro de execução: escreva
seeders idempotentes quando puderem rodar mais de uma vez.

## Testes

Os testes unitários usam um `resty.mysql` falso e não precisam de banco:

```sh
lua cli.lua test mysql-adapter
lua cli.lua test model
```

Os testes de integração (`tests/test-mysql-integration.lua`) só rodam com
credenciais no ambiente; sem `DB_PASSWORD` imprimem `SKIP` e saem com sucesso.
O banco precisa existir; o teste cria e remove as tabelas `it_users`,
`it_posts` e `crescent_test_migrations`.

```sh
DB_HOST=127.0.0.1 DB_PORT=3306 DB_USER=root DB_PASSWORD=segredo \
DB_TEST_NAME=crescent_test lua cli.lua test mysql-integration
```
