# {{project}} — guide for AI models

This project uses **Crescent 2**, a Lua web framework on **OpenResty** (Nginx +
LuaJIT) with **MySQL**. Read this file before writing code here. It is the
contract for how code in this project is organized and which APIs exist. Do not
invent APIs: if something is not listed here, check `crescent/` (the framework
source is in the repository) or ask.

Full docs (Portuguese): https://crescent.tyne.com.br · framework source:
https://github.com/daniel-m-tfs/crescent-framework

## 1. Runtime model (read first)

- Lua version is **LuaJIT (Lua 5.1)**: no `//`, no integer subtype, no `<const>`,
  use `#t`, `table.insert`, `unpack` (not `table.unpack`), `goto` is available.
- `app.lua` builds the app **once per Nginx worker** and returns it; Nginx calls
  `require("app"):run()` per request. Module-level variables are shared by all
  requests of a worker: **never keep request data in module locals**; use
  `ctx.state`.
- All I/O (MySQL, Redis, HTTP client, SMTP) uses non-blocking cosockets. **Never** use
  blocking libraries (luasocket, io.popen, os.execute, luasql) in request code.
- Development: `lua_code_cache off` (code reloads per request). Production:
  code is cached; reload Nginx to deploy.
- Every environment variable read at runtime needs an `env NAME;` directive in
  `nginx.conf` **and** every file in `conf/`, otherwise it is empty in workers.
- Errors convention: functions return `value` or `nil, err`. Raise (`error`)
  only for programmer errors or for 4xx tables (see Errors).

## 2. Project layout

```
app.lua                 builds the app: middleware + module registration
config/<env>.lua        config per APP_ENV (development, test, production)
src/<module>/
  init.lua              Module.register(app) — the only public entry point
  controllers/<name>.lua   route handlers: read ctx, call services, respond
  services/<name>.lua      business logic: no ctx, take `db`, return value or nil, err
  models/<name>.lua        Model:extend({...})
  routes/<name>.lua        function(app, prefix) registering named routes
  middleware/<name>.lua    optional module middleware
  jobs/<name>.lua          background jobs: handle(payload, job) (crescent.queue)
src/middleware/         app-wide middleware
views/                  etlua templates (layout.etlua + pages)
public/                 static files served by Nginx at /public/
migrations/             YYYYMMDDHHMMSS_<name>.lua (up/down)
seeds/                  <name>.lua seeders (prefix 01_, 02_ to order)
storage/                uploads (upload_root = "storage")
tests/                  test-*.lua (unit, run on resty) + test-http.sh (HTTP smoke)
crescent/  cli/         the framework itself (vendored; do not edit for app work)
nginx.conf  conf/       Nginx configs (dev / production / docker)
```

Layering rules:
- Controllers never build SQL; services never touch `ctx`.
- Models declare data rules (`fillable`, `validates`, `casts`, `relations`).
- A module only exposes `register(app)`; other modules `require` its
  services/models directly when needed (`require("src.users.models.user")`).
- File names are `snake_case`; tables are plural snake_case (`blog_posts`);
  Lua module tables are PascalCase (`BlogPostController`).

## 3. CLI (run from the project root)

```bash
lua cli.lua help
lua cli.lua setup                         # fresh git, DB credentials, start Docker
lua cli.lua run [--logs]                  # Docker: app + MySQL, hot reload
lua cli.lua rerun [--fresh]               # rebuild image (Dockerfile/deps/nginx changed)
lua cli.lua stop
lua cli.lua make:module Product           # full CRUD module + test + migration
lua cli.lua make:controller Report shop   # src/shop/controllers/report.lua
lua cli.lua make:service|make:model|make:routes <name> [module]
lua cli.lua make:middleware <name> [module]
lua cli.lua make:job <name> [module]      # src/<module>/jobs/<name>.lua
lua cli.lua make:test <name>              # tests/test-<name>.lua
lua cli.lua make:migration create_orders_table | add_total_to_orders
lua cli.lua make:seeder 01_admin_user
lua cli.lua db:migrate | db:rollback | db:status | db:seed [name]
lua cli.lua routes                        # METHOD PATH NAME
lua cli.lua queue:work | queue:status | queue:failed | queue:retry <id|all>   # QUEUE_DRIVER=redis
lua cli.lua cache:clear
lua cli.lua test [filter]                 # unit tests; filter by file name
lua cli.lua test:http                     # tests/test-http.sh against real OpenResty
```

Inside Docker use `docker compose exec app bin/crescent <command>` (same
commands). Generators never overwrite files. The CLI reads `.env`.

## 4. Recipe: adding a feature

1. `lua cli.lua make:module Order` → `src/order/{init.lua,controllers,services,models,routes}`,
   `tests/test-order-module.lua`, `migrations/<ts>_create_orders_table.lua`.
2. Edit the migration (columns, indexes, foreign keys). One schema change per
   migration (MySQL DDL commits implicitly).
3. Edit the model: `fillable`, `hidden`, `validates`, `casts`, `relations`.
4. Edit the controller `schema` (request validation) and the service logic.
5. Register in `app.lua`: `require("src.order").register(app)`.
6. `lua cli.lua db:migrate`, then write tests and run `lua cli.lua test order`.

## 5. Routes and controllers

```lua
-- src/order/routes/order.lua
local controller = require("src.order.controllers.order")

return function(app, prefix)
    app:get(prefix, controller.index, "orders.index")
    app:get(prefix .. "/{id}", controller.show, "orders.show")
    app:post(prefix, app:validated(controller.schema, controller.store), "orders.store")
    app:put(prefix .. "/{id}", app:validated(controller.schema, controller.update), "orders.update")
    app:delete(prefix .. "/{id}", controller.destroy, "orders.destroy")
end
```

- Methods: `app:get/post/put/patch/delete/options/head(path, handler, name?)`.
- Params: `/users/{id}`, optional `/posts/{slug?}`, catch-all last segment
  `/files/{path*}`. **Params are always strings** (`tonumber(ctx.params.id)`).
- Static routes win over parameterized ones. HEAD falls back to GET. Wrong
  method → 405 with `Allow`; unknown path → 404 `route_not_found`.
- Groups: `app:group("/api/v1", function(api) api:get(...) end)`.
- Named routes: `app:route("orders.show")` → `"/orders/{id}"`.

```lua
-- src/order/controllers/order.lua
local OrderService = require("src.order.services.order")

local OrderController = {}

OrderController.schema = {
    total = { required = true, number = true, min = 0 },
}

function OrderController.show(ctx)
    local order, err = OrderService.find(ctx.db, ctx.params.id)
    if err then return ctx:error(500, "unable to load order", ctx.debug and err or nil, "order_load_failed") end
    if not order then return ctx:error(404, "order not found", nil, "order_not_found") end
    return ctx:json(200, { data = order })
end

return OrderController
```

### ctx — request

| Field | Content |
| --- | --- |
| `ctx.params` | route params (strings) |
| `ctx.query` | query string (strings; repeated key → list) |
| `ctx.body` | decoded JSON or form table (other content types: string) |
| `ctx.raw_body` | raw body |
| `ctx.files` | multipart files `{ filename, content_type, size, path, field }` |
| `ctx:get_header(name)` | header, case-insensitive |
| `ctx:get_bearer()` | token from `Authorization: Bearer`, or nil |
| `ctx:cookie(name)` / `ctx:signed_cookie(name)` | cookies |
| `ctx.method`, `ctx.path`, `ctx.route` | method, path, matched route pattern |
| `ctx.request_id`, `ctx.remote_addr` | request id (`X-Request-Id`), client IP |
| `ctx.state` | per-request table (e.g. `ctx.state.user`, `ctx.state.log`) |
| `ctx.db`, `ctx.config`, `ctx.app`, `ctx.debug` | DB adapter, config, app, debug flag |
| `ctx.session` | session (when the session middleware is on) |

### ctx — responses (return them)

`ctx:json(status, value)`, `ctx:text(status, s)`, `ctx:html(status, s)`,
`ctx:view("page.etlua", data, { layout = "layout.etlua", status = 200 })`,
`ctx:redirect("/path", 302)` (local paths only; other hosts need
`{ allowed_hosts = { "x.com" } }`), `ctx:no_content()` (204),
`ctx:error(status, message, details?, code)`, `ctx:header(name, value)`,
`ctx:set_cookie(name, value, opts)`, `ctx:clear_cookie(name)`,
`ctx:save_upload(file, "relative/path", { overwrite = true })`.

- Returning a table sends 200 JSON; returning a string sends 200 text.
  Returning nothing without responding is a bug → 500 `empty_response`.
- Empty lists: `require("crescent.json").array(list)`, otherwise `{}` is sent.
- Models are not JSON: call `model:to_table()` (respects `hidden`).

## 6. Validation

`app:validated(schema, handler, source)` (source `"body"` default, or
`"query"`) → 422 `validation_failed` with `details = { field = { { code, message } } }`.
Manual: `local ok, errors = ctx:validate(schema, "query")`.

Rules: `required`, `type = "string"` (exact Lua type), `string`, `number`,
`min_length`, `max_length`, `length`, `email`, `format` (Lua pattern), `min`,
`max`, `range = { a, b }`, `custom = function(v) return ok, "message" end`.
Missing fields only fail with `required`. Query/form values are strings, so
`number = true` only passes for JSON bodies; use `format = "^%d+$"` for query.

## 7. Errors

JSON shape: `{ "status": 409, "code": "email_taken", "error": "message", "details": ... }`.
Always pass a stable `code` (snake_case) to `ctx:error`.

- Uncaught `error("...")` → 500 `internal_error`, logged with request id;
  details only in responses when `debug = true`.
- `error({ status = 403, code = "no_access", public_message = "no access" })`
  → that 4xx response, not logged as an error (`Model:find_or_fail` uses this:
  404 `model_not_found`).
- `app:on_error(function(ctx, err) return ctx:json(500, {...}) end)` customizes 500s.
- Framework codes: `route_not_found` 404, `method_not_allowed` 405,
  `validation_failed` 422, `model_not_found` 404, `malformed_json`/`malformed_form` 400,
  `invalid_redirect` 400, `internal_error`/`empty_response` 500, `template_error` 500.

## 8. Middleware

```lua
app:use(function(ctx, next)
    if not ctx:get_header("X-Api-Key") then
        return ctx:error(401, "unauthorized", nil, "unauthorized")   -- block: do not call next
    end
    ctx.state.client = "internal"
    return next()                                                   -- continue
end)
```

- Global, in `app:use` order, before routing. Code after `next()` runs after the
  handler; to change headers then, use `ctx.res:before_flush(function(res) ... end)`.
- Per route: `auth.protect(middleware_or_list, handler)`.
- Built-in: `Crescent.middleware.security_headers.create()`,
  `Crescent.middleware.request_log.create({ skip = fn })`, `crescent.middleware.cors`,
  `crescent.middleware.rate_limit`, `crescent.middleware.session`,
  `crescent.middleware.csrf`, `crescent.middleware.auth`.

## 9. Database (MySQL only)

Raw SQL, always with `?` bindings:

```lua
local rows, err = ctx.db:query("SELECT id, name FROM users WHERE email = ?", { email })
local result, err = ctx.db:execute("UPDATE users SET name = ? WHERE id = ?", { name, id })
-- result = { affected_rows, insert_id }; errors: nil, err, errno, sqlstate, kind
-- kind: unique_violation | foreign_key_violation | deadlock | lock_timeout | connection | bind | query
```

### Models

```lua
-- src/users/models/user.lua
local Model = require("crescent.model")

return Model:extend({
    table = "users",
    fillable = { "name", "email", "password" },   -- only these are mass-assigned
    hidden = { "password" },                      -- excluded from to_table()
    timestamps = true,                            -- created_at / updated_at
    soft_deletes = false,                         -- true needs deleted_at
    casts = { active = "boolean", price = "number" },   -- string|number|integer|boolean
    validates = {
        name = { required = true, min_length = 3 },
        email = { required = true, email = true, unique = true },
    },
    relations = {
        posts = { type = "has_many", model = "src.blog.models.post" },
        profile = { type = "has_one", model = "src.users.models.profile" },
        -- in Post: user = { type = "belongs_to", model = "src.users.models.user" }
    },
    before_save = function(user) user.email = user.email:lower() end,
})
```

```lua
local user, errors = User:create({ name = "Ada", email = "ada@example.com" })  -- nil, errors on failure
local user = User:find(id)                 -- model or nil
local user = User:find_or_fail(id)         -- raises 404 model_not_found
local list = User:where("role", "admin"):order_by("name"):get()
local one = User:where("email", email):first()
local total = User:count()
local page = User:where("active", 1):page(ctx.query.page, ctx.query.per_page)
-- page.data = { models }, page.meta = { page, per_page, total, last_page, from, to }
user.name = "New"; user:save()             -- updates changed columns only
user:update({ name = "New" })
user:delete()                              -- soft delete if enabled; force_delete(), restore()
User:with("posts", "posts.comments"):get() -- eager loading, no N+1
user:get("posts")                          -- lazy load
User:with_trashed() / User:only_trashed()
return ctx:json(200, { data = user:to_table() })
```

- `create/save/update` return the model or `nil, errors`; validation and
  unique-key errors are tables `{ field = { { code, message } } }`, DB failures
  are strings.
- Every model method accepts an optional last argument: the adapter (`db` or `tx`).
- Primary key and `*_id` columns are numbers (MySQL BIGINT strings are converted).
- Hooks: `before_save`, `before_create`, `before_update`, `after_create`,
  `after_update`, `after_save`, `before_delete`, `after_delete`; a `before_*`
  returning `false` cancels.
- If a column is named like a model method (`table`, `save`, `update`), use
  `model:get("col")` / `model:set("col", v)`.

### Query builder (plain tables, no casts)

```lua
local QueryBuilder = require("crescent.database.query_builder")

local rows = QueryBuilder.table("users")
    :select("users.id", "users.name", "profiles.bio")
    :left_join("profiles", "profiles.user_id", "users.id")
    :where("active", true)
    :where("age", ">=", 18)
    :where(function(q) q:where("role", "admin"):or_where("verified", true) end)
    :where_in("country", { "BR", "PT" })
    :order_by("users.name", "ASC")
    :limit(20)
    :get()
```

Filters: `where`, `or_where`, `where_in`, `where_not_in`, `where_null`,
`where_not_null`, `where_raw(sql, bindings)`. Joins: `join`, `left_join`,
`right_join`. Order: `order_by`, `limit`, `offset`, `paginate(page, per)`.
Run: `get`, `first`, `count`, `exists`, `page`. Write: `insert(values)`,
`update(values)`, `delete()` (update/delete without `where` raise).
`to_sql()` returns `sql, bindings`. `QueryBuilder.raw(sql, bindings)`.
Operators: `= != <> < <= > >= LIKE NOT LIKE`; `where("col", nil)` → `IS NULL`.

### Transactions

```lua
local Database = require("crescent.database")

local order, err = Database.transaction(function(tx)
    local order = assert(Order:create(attributes, tx))   -- pass tx everywhere
    tx:execute("UPDATE stock SET qty = qty - 1 WHERE product_id = ?", { order.product_id })
    return order
end)   -- COMMIT on return; ROLLBACK on error, false, or nil, err
```

### Migrations and seeders

```lua
-- migrations/20260101120000_create_orders_table.lua
return {
    up = function(db)
        return {
            [[CREATE TABLE `orders` (
                `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                `user_id` BIGINT UNSIGNED NOT NULL,
                `total` DECIMAL(10,2) NOT NULL,
                `created_at` TIMESTAMP NULL,
                `updated_at` TIMESTAMP NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
            "CREATE INDEX `orders_user_id` ON `orders` (`user_id`)",
        }
    end,
    down = function(db) return "DROP TABLE `orders`" end,
}

-- seeds/01_admin_user.lua — runs in a transaction; keep it idempotent
local User = require("src.users.models.user")
return function(db)
    if not User:where("email", "admin@example.com"):first(db) then
        assert(User:create({ name = "Admin", email = "admin@example.com" }, db))
    end
end
```

## 10. Security

```lua
local auth = require("crescent.middleware.auth")
local password = require("crescent.security.password")

app:get("/me", auth.protect(auth.jwt(), function(ctx) return ctx:json(200, ctx.state.user) end))

-- login
local user = User:where("email", ctx.body.email):first()
if not user or not password.verify(ctx.body.password, user.password) then
    return ctx:error(401, "invalid credentials", nil, "invalid_credentials")
end
return auth.generate_token_pair(user)   -- { access_token, refresh_token, token_type, expires_in, refresh_expires_in }
```

- `auth.jwt({ get_user = function(payload, ctx) return User:find(payload.user_id) end, optional = false })`
  sets `ctx.state.user` and `ctx.state.jwt`; secret from `JWT_SECRET` (32+ bytes).
- `auth.verify_refresh_token(token)` → `ok, payload`; `auth.revoke_token(payload)`.
- Others: `auth.bearer(fn)`, `auth.basic(fn, { realm })`, `auth.api_key("X-Api-Key", fn)`
  where `fn` returns `true, user` or `false, "message"`. Compare secrets with
  `auth.secure_compare(a, b)`.
- Passwords: `password.hash(plain)`, `password.verify(plain, hash)`,
  `password.needs_rehash(hash)` (PBKDF2, slow by design: rate-limit login).
- CORS (register before auth): `require("crescent.middleware.cors").create({ origins = {...}, credentials = true })`.
- Rate limit: `require("crescent.middleware.rate_limit").create({ limit = 5, window = 60, prefix = "rl:login:" })` → 429 `rate_limited`.
- Sessions: `app:use(require("crescent.middleware.session").create())`;
  `ctx.session:get/set/delete/flash/get_flash/regenerate/destroy`. Call
  `regenerate()` after login.
- CSRF (after session): `app:use(require("crescent.middleware.csrf").create({ skip = fn }))`;
  forms use `<%- csrf_field() %>`, AJAX sends `X-CSRF-Token`. Tokens are
  masked per request (BREACH-safe), so `csrf_token()` changes on every page;
  never compare tokens yourself. `session:regenerate()` rotates the secret.
- Cookies are `HttpOnly`, `SameSite=Lax`, `Secure` outside debug. Signed
  cookies/sessions/CSRF use `APP_KEY` (32+ chars).
- Uploads: validate `content_type`/size yourself; save with `ctx:save_upload`
  only under `upload_root`; never trust `filename`.
- Never log secrets; `crescent.logger` redacts password/token/secret/cookie fields.

## 11. Views

etlua templates in `views/`: `<%= value %>` escapes HTML, `<%- html %>` does
not (only for trusted HTML such as `content` or `csrf_field()`). The layout
receives the page in `content`.

```lua
return ctx:view("orders/index.etlua", { title = "Orders", orders = list }, { layout = "layout.etlua" })
```

## 12. Cache and queues

Configured in `config/<env>.lua` (`cache`, `queue`, `redis`). Drivers come from
`CACHE_DRIVER` / `QUEUE_DRIVER`: `shared` (default: this server's memory, no
extra service, queue jobs run inside OpenResty and are lost on restart) or
`redis` (durable, multi-server; jobs run in `lua cli.lua queue:work` / the
Docker `worker` service). Tests use `queue.driver = "sync"` (push runs the job
immediately and raises its errors).

```lua
-- Cache: JSON values (tables, strings, numbers, booleans); nil is never cached.
ctx.cache:set("user:" .. id, user, 300)        -- ttl seconds (default config.cache.ttl; 0 = forever)
local user = ctx.cache:get("user:" .. id)      -- nil on miss (and on backend errors)
ctx.cache:delete("user:" .. id)                -- add, has, pull, incr(key, n, ttl), decr, flush
local stats = ctx.cache:remember("stats", 60, function() return StatsService.compute(ctx.db) end)
```

Jobs are modules with `handle(payload, job)`; the job name is the module path.
Generate with `lua cli.lua make:job send_welcome users`:

```lua
-- src/users/jobs/send_welcome.lua
local SendWelcome = { queue = "default", attempts = 3, backoff = { 10, 60, 300 }, timeout = 60 }

function SendWelcome.handle(payload, job)   -- job: id, attempts, db, cache, config, dispatch, log
    local user = User:find(payload.user_id)
    if not user then return end
    local ok, err = Mail.new():send({ to = user.email, subject = "Welcome", text = "..." })
    if not ok then error(err) end           -- or `return false, err`: retried after backoff
end

function SendWelcome.failed(payload, err, job) end   -- optional, after the last attempt
return SendWelcome
```

```lua
ctx.queue:push("src.users.jobs.send_welcome", { user_id = user.id })             -- -> job id
ctx.queue:push("src.users.jobs.send_welcome", { user_id = user.id }, { delay = 60, queue = "mail" })
```

- Payloads must be JSON-serializable: pass ids, not models or functions.
- Delivery is at-least-once (crash/timeout re-runs a job): make `handle`
  idempotent and keep `timeout` above the job's longest run.
- Never `ngx.sleep`-poll for job results in a request; respond 202 and let the
  client poll a resource the job updates.
- Long CPU work in jobs competes with requests when workers are embedded
  (`shared` driver); move it to `redis` + a worker process.
- Queue CLI (redis driver): `queue:work`, `queue:status`, `queue:failed`,
  `queue:retry <id|all>`, `queue:clear-failed`, `cache:clear`.

## 13. Utilities

- HTTP client: `local api = require("crescent.http_client").new({ base_url = "...", timeout = 5 })`;
  `api:get(url, { params = {...} })`, `api:post(url, table_as_json)` → `res`
  (`res.status`, `res.data`) or `nil, err` (also for status >= 400).
- Mail: `require("crescent.mail").new():send({ to = "a@b.com", subject = "...", text = "...", html = "..." })`;
  `send_template(to, subject, "emails/x.etlua", data)`. SMTP_* env vars.
- Logger: `ctx.state.log:info("order created", { order_id = id })` (request_log
  middleware adds it); `require("crescent.logger").new({ level = "info" })`.
- JSON: `require("crescent.json")` → `encode`, `decode`, `array`.
- Env/config: `require("crescent.env").get("NAME", default)`, `.number`,
  `.boolean`; app config lives in `config/<APP_ENV>.lua`.
- Health: `/health` (liveness) and `/ready` (DB and, when used, Redis checks) come from `src/health`.

## 14. Tests

Unit tests run on OpenResty's LuaJIT and call the app without a server:

```lua
-- tests/test-orders.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local tests = require("crescent.utils.tests")
local Crescent = require("crescent")
local json = require("crescent.json")

local function app()
    local instance = Crescent.new({ environment = "test", debug = true, logger = function() end })
    require("src.order").register(instance)
    return instance
end

local function call(instance, method, path, body, query)
    local writer = { headers = {} }
    instance:handle({ method = method, path = path, headers = {}, query = query or {}, body = body }, writer)
    return writer.status, writer.body ~= "" and json.decode(writer.body) or nil
end

local function rejects_invalid_orders()
    local status, body = call(app(), "POST", "/orders", {})
    tests.assertEquals(status, 422)
    tests.assertEquals(body.code, "validation_failed")
end

assert(tests.runSuite("Orders", { rejects_invalid_orders = rejects_invalid_orders }))
```

- Without a database `ctx.db` is nil (generated controllers answer 503). For
  DB logic, inject a fake adapter: `instance.db = { query = fn, execute = fn }`
  where `query(sql, bindings)` returns rows and `execute` returns
  `{ insert_id, affected_rows }`.
- Assertions: `assertEquals`, `assertNotEquals`, `assertTrue`, `assertFalse`,
  `assertNil`, `assertNotNil`, `assertType`, `assertContains`,
  `assertNotContains`, `assertMatches`, `assertTableEquals`, `assertError`,
  `assertNoError`.
- Add new routes to `tests/test-http.sh` with `expect <status> <path> [text]`.
- Always run `lua cli.lua test` after changes.

## 15. Do / don't

Do:
- Use the generators, then edit; keep the controllers/services/models/routes split.
- Validate input with schemas; return errors with stable codes.
- Use `?` bindings or the query builder; pass `tx` inside transactions.
- Add `env NAME;` to all Nginx confs for new env vars, and add them to `.env.example`.
- Write a test for every route and service you add.

Don't:
- Don't edit `crescent/` or `cli/` for application features.
- Don't concatenate user input into SQL, shell commands, file paths or HTML.
- Don't use blocking I/O, global state per request, or `os.exit` in app code.
- Don't commit `.env` or secrets; don't print passwords.
- Don't use Lua 5.3+ syntax or libraries not installed in `lua_modules/`
  (available: etlua, lua-resty-http, lua-resty-mail, plus OpenResty's bundled
  lua-resty-mysql, lua-resty-openssl, cjson).
