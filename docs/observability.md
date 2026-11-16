# Observabilidade

## Logs estruturados — `crescent.logger`

Cada entrada é uma linha JSON gravada no error log do Nginx (ou stderr fora
do OpenResty). Campos sensíveis são mascarados automaticamente.

```lua
local Logger = require("crescent.logger")
local log = Logger.new({ level = "info", fields = { service = "api" } })

log:info("login", { user_id = 7, password = "x" })
-- {"service":"api","user_id":7,"password":"[REDACTED]","level":"info","msg":"login"}

log:with({ request_id = ctx.request_id }):warn("cota excedida")
Logger.redact(tabela, { "cpf" })   -- cópia mascarada; padrões extras opcionais
```

- Níveis: `debug`, `info`, `warn`, `error` (abaixo do nível configurado é ignorado).
- Mascarados (substring, sem diferenciar maiúsculas): `password`, `passwd`,
  `secret`, `token`, `authorization`, `cookie`, `api_key`, `credit_card`,
  `card_number`, `cvv`, `private_key`. Acrescente padrões com `redact = { ... }`.
- Strings longas são truncadas (2 KB); referências circulares viram `[circular]`.

A aplicação usa o logger para registrar todo erro 500 com `request_id`,
método e rota. Passe o seu com `Crescent.new({ logger = Logger.new{...} })`
(também aceita uma função `function(level, message, fields)`).

## Log por requisição — `crescent.middleware.request_log`

```lua
app:use(Crescent.middleware.request_log.create({
    skip = function(ctx) return ctx.path == "/health" or ctx.path == "/ready" end,
}))
-- dentro da action: ctx.state.log:info("pedido criado", { order_id = id })
```

Uma entrada por requisição com `method`, `path`, `route`, `status`,
`duration_ms`, `remote_addr`, `user_id` (de `ctx.state.user`) e `request_id`.
Status 5xx sai como `error`, 4xx como `warn`. O `access_log` do Nginx
continua sendo a fonte de verdade do tráfego.

## Health e readiness — `crescent.health`

```lua
require("crescent.health").register(app, {
    service = "api",
    checks = {                       -- padrão: { database = SELECT 1 } quando há banco
        database = require("crescent.health").checks.database,
        cache = function(ctx) return redis_ping() end,   -- true | nil, err
    },
})
```

- `GET /health` (liveness): 200 enquanto o worker responde; não consulta dependências.
- `GET /ready` (readiness): 200 se todos os checks passam, 503 caso contrário,
  com o status e a duração de cada check. Erros só aparecem no corpo com
  `debug = true`; sempre vão para o log.

Use `/ready` para o balanceador decidir se envia tráfego e `/health` para
reiniciar o processo.
