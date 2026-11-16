# NEWCrescent

Crescent rebuilt for Lua + OpenResty, preserving the existing Crescent module style while delegating HTTP runtime responsibilities to OpenResty/Nginx.

## Requirements

- OpenResty with LuaJIT
- LuaRocks for optional database adapters
- A supported database adapter configured by the application

## Development

```bash
cp .env.example .env
/opt/homebrew/opt/openresty/bin/openresty -p "$PWD/" -c nginx.conf
```

The application loads `config.<APP_ENV>` through `crescent.config`; when
`APP_ENV` is not set, it uses `development`. Environment files are a local
convenience only, and production secrets should come from the process
environment or a secret manager.

Pure input validation is available through `crescent.validation`. Schemas use
rules such as `required`, `type`, `string`, `number`, `email`, `min_length`,
`max_length`, `length`, `range`, `format`, and `custom`. Validation returns
`true, {}` for valid input or `false, errors` with stable error `code` and
public `message` fields.
Actions can enforce a schema with `app:validated(schema, action, source)`;
`source` defaults to `body` and can be `params`, `query`, or `headers`. Invalid
input returns HTTP `422` before the wrapped action runs.

Framework errors include a stable `code`, such as `route_not_found`,
`method_not_allowed`, `validation_failed`, and `internal_error`. Internal
details are included only when application debug mode is enabled.
An environment config may provide `error_handler(ctx, error)`; it must return a
response. If it raises or returns `nil`, Crescent uses the safe internal error
response instead.
Every response includes an `X-Request-Id` header. A valid upstream request ID
is preserved; otherwise Crescent generates one for the request.

Para desenvolvimento, o `nginx.conf` usa `lua_code_cache off` para recarregar
modulos sem restart. Em producao, habilite `lua_code_cache on`.

Teste manual:

```bash
curl http://127.0.0.1:8080/health
```

The first vertical slice exposes `GET /health`.
The OpenResty entrypoint reads the request body before dispatching the action;
actions access it through `ctx.body`. JSON requests are decoded using
`cjson.safe`; the original text remains available as `ctx.raw_body`, and
malformed JSON returns `400 malformed_json` before dispatch.
URL-encoded forms are decoded into `ctx.body`, including `+` spaces, percent
encoding, and repeated fields as arrays; malformed input returns
`400 malformed_form`.

Routes support required parameters such as `/users/{id}`, optional parameters
such as `/users/{id?}`, and final-segment wildcards such as
`/assets/{path*}`. Matching precedence is literal, parameter, then wildcard.
Routes can be grouped and named through `app:group("/api", ...)`, a third
argument such as `app:get("/health", action, "api.health")`, and
`app:route("api.health")`.
Application middleware uses `app:use(function(ctx, next) ... end)`. Middleware
can mutate `ctx.state`, wrap `next()`, or return a response to short-circuit
the request before routing.

## Tests

The initial tests are pure Lua and do not require OpenResty:

```bash
lua cli.lua test
# or
./test.sh

# Requires OpenResty and curl
lua cli.lua test:http
```

The test suites use the adapted `crescent.utils.tests` helper from the original
Crescent Framework. It keeps the assertion and suite API familiar while
remaining independent of Luvit and the original `json` module.

The `test:http` command starts the local OpenResty configuration and verifies
real HTTP responses for health, 404, 405, `Allow`, and `X-Request-Id`.

Database access starts with the driver-independent contract in
`crescent.database.adapter`. Drivers are injected and must implement
`connect`, `query`, `execute`, `transaction`, and `close`; no database driver
is loaded by the framework yet.
`crescent.database.query_builder` generates SQL and bindings separately. Table
and column identifiers are allowlisted; values are always emitted as `?`
bindings and are never interpolated into SQL.
Builders can execute through an injected adapter with `fetch(adapter)` or
`execute(adapter)`; the builder owns SQL generation, while the adapter owns
connections and result handling.
Declarative models are available through `crescent.model`. The current
foundation supports `table`, `fillable`, `guarded`, `hidden`, `timestamps`,
validation, `get`/`set`, and safe `to_table` serialization; persistence and
soft-delete state are available. Persistence remains separate database work;
`save(adapter)` now persists inserts and updates through the injected adapter;
insert adapters should return `{ insert_id = ... }` when the database creates a
primary key, so subsequent saves can target the row safely;
models with `validates = { field = { unique = true } }` perform a parameterized
uniqueness lookup through the injected adapter during `save`; a real database
unique constraint is still required for race-free enforcement;
soft-delete `delete` and `restore` remain state operations until database
mutation wiring is added.
Relations are declared with `relations` and loaded explicitly through
`model:relation(name, adapter)`. They never run automatically during
serialization, preventing hidden N+1 queries.
Views use the installed ETLua engine through `crescent.view`. `<%= value %>`
is HTML-escaped, while `<%- value %>` is reserved for explicitly trusted HTML.
Template names are constrained to the configured local views root; user-supplied
templates and path traversal are rejected.
Actions can return `ctx:view("hello.etlua", data)`; this sends an HTML response
with the configured application view renderer.
The renderer also exposes `partial(name, data)` and `render_layout(layout,
content, data)` for explicit composition within the configured views root.
Helpers can be registered with `view:helper("name", fn)` and are available to
templates without overwriting keys passed in page data.
Template caching is enabled by default and can be disabled with
`View.new(root, { cache = false })`; `clear(name)` and `reload(name)` invalidate
individual compiled templates.
Migrations use `crescent.database.migration`: migrations are sorted by name,
executed individually through the adapter, and recorded only after success.
The runner does not wrap DDL in an assumed transaction.
The first concrete driver is [pgmoon](https://github.com/leafo/pgmoon), a pure
Lua PostgreSQL driver designed for OpenResty cosockets. It is wrapped by
`crescent.database.pgmoon`, loaded lazily, and configured with `DB_*` values by
the application; tests use an injected fake and do not require a live database.

The imported CLI currently exposes `test` and `help`. Database, server, and
code-generation commands remain disabled until their OpenResty-compatible
implementations are ready.
