# Cache e filas

`crescent.cache` e `crescent.queue` funcionam **sem nenhum serviço extra**, na
memória compartilhada do OpenResty (`lua_shared_dict`). O Redis é opcional e
entra quando você precisa de durabilidade ou de mais de um servidor. O
`lua-resty-redis` já vem com o OpenResty, então não há dependência nova.

| Driver | Cache | Fila | Quando usar |
|---|---|---|---|
| `shared` (padrão) | memória dos workers de um servidor, LRU | jobs executados dentro do próprio OpenResty | um servidor, jobs que podem se perder num restart (e-mails de boas-vindas, webhooks com retry do lado de lá) |
| `redis` | compartilhado entre servidores, sobrevive a restart | durável, worker separado (`queue:work`) | mais de uma instância, jobs que não podem se perder |
| `sync` | — | executa o job dentro do `push()` | testes e scripts |

## Configuração

`config/<env>.lua` (os projetos novos já vêm com isso):

```lua
redis = {
    host = Env.get("REDIS_HOST", "127.0.0.1"),
    port = Env.number("REDIS_PORT", 6379),
    password = Env.get("REDIS_PASSWORD"),
    database = Env.number("REDIS_DB", 0),
},
cache = {
    driver = Env.get("CACHE_DRIVER", "shared"),
    prefix = "minha_app:cache:",
    ttl = 3600,                       -- padrão em segundos; 0 = sem expiração
},
queue = {
    driver = Env.get("QUEUE_DRIVER", "shared"),
    prefix = "minha_app:queue:",
    attempts = 3,                     -- padrões; cada job pode sobrescrever
    backoff = { 10, 60, 300 },        -- segundos entre tentativas (número ou lista)
    timeout = 60,                     -- após isso o job volta para a fila (redis)
    workers = {
        embedded = nil,               -- padrão: true com "shared", false com "redis"
        concurrency = 1,              -- loops por worker do nginx
        queues = { "default" },       -- ordem = prioridade
        sleep = 1,                    -- segundos entre consultas quando vazia
    },
},
```

O cliente Redis só é criado quando algum driver é `redis` (ou com
`redis.enabled = true`). Nesse caso o `/ready` também verifica o Redis.

Os `lua_shared_dict crescent_cache` e `crescent_queue` e as variáveis
`REDIS_*`, `CACHE_DRIVER` e `QUEUE_DRIVER` já estão em `nginx.conf` e
`conf/*.conf`.

## Cache: `ctx.cache`

```lua
ctx.cache:set("user:1", user, 300)          -- tabelas, strings, números, booleanos (JSON)
ctx.cache:get("user:1")                     -- valor ou nil
ctx.cache:get("user:1", default)
ctx.cache:add("lock:import", true, 60)      -- só grava se não existir -> true/false
ctx.cache:has("user:1")
ctx.cache:delete("user:1")                  -- alias: forget
ctx.cache:pull("token")                     -- lê e apaga
ctx.cache:incr("visits")                    -- contador atômico; incr(key, n, ttl), decr
ctx.cache:flush()                           -- shared: limpa o dict; redis: só as chaves do prefixo

local stats = ctx.cache:remember("stats", 60, function()
    return StatsService.compute(ctx.db)
end)
```

- `remember` evita stampede: só um chamador calcula por vez. Os outros esperam
  até `lock_wait` segundos (padrão 5) pelo valor e só então calculam por conta
  própria. Um resultado `nil` não é guardado, e erros da função propagam.
- Falha do backend nunca lança erro. `get` devolve `nil, err` (cache miss) e
  `remember` recalcula. Uma queda do Redis deixa a app mais lenta, mas ela
  continua funcionando.
- `nil` não pode ser cacheado; `set` com função ou userdata lança erro.

## Filas: `ctx.queue`

Um job é um módulo Lua com `handle(payload, job)`. O nome do job é o caminho
do módulo, então qualquer processo consegue carregá-lo sem registro:

```bash
lua cli.lua make:job send_welcome users     # src/users/jobs/send_welcome.lua
```

```lua
-- src/users/jobs/send_welcome.lua
local SendWelcome = {
    queue = "mail",          -- opcionais: padrões vindos de config.queue
    attempts = 5,
    backoff = { 30, 120 },
    timeout = 120,
}

function SendWelcome.handle(payload, job)
    local user = User:find(payload.user_id)
    if not user then return end                     -- nada a fazer: sucesso
    local ok, err = Mail.new():send({ to = user.email, subject = "Bem-vindo", text = "..." })
    if not ok then error(err) end                   -- ou `return false, err`: tenta de novo
end

-- Opcional: roda depois da última tentativa.
function SendWelcome.failed(payload, err, job)
    job.log("error", "boas-vindas não enviadas", { user_id = payload.user_id })
end

return SendWelcome
```

```lua
ctx.queue:push("src.users.jobs.send_welcome", { user_id = user.id })
ctx.queue:push("src.users.jobs.send_welcome", { user_id = user.id }, {
    delay = 60, queue = "mail", attempts = 3, backoff = 10, timeout = 30,
})
```

`push` devolve o id do job (ou `nil, err` se o backend falhar). Ele lança
erro se o job não existir, se o payload não for serializável em JSON ou se as
opções forem inválidas.

O segundo argumento do `handle` traz `id`, `name`, `queue`, `attempts`,
`max_attempts`, `db`, `cache`, `config`, `app`, `dispatch(name, payload,
options)` (para enfileirar outro job) e `log(level, message, fields)`.

**Entrega pelo menos uma vez.** Um job pode rodar de novo se o worker morrer
ou se passar do `timeout`. Escreva handlers idempotentes, por exemplo checando
se o e-mail já foi enviado antes de enviar. O `timeout` precisa ser maior que
a execução mais longa do job. Com Redis, se o job passar do `timeout`, ele
volta para a fila e outro worker o pega.

### Onde os jobs rodam

- **Workers embutidos** (padrão com `shared`): o `init_worker_by_lua` dos confs
  chama `app:start_workers()`, que inicia `concurrency` loops em cada worker do
  nginx, sem processo extra. Os jobs rodam no mesmo processo que atende as
  requisições, então jobs pesados de CPU competem com elas.
- **Worker dedicado** (padrão com `redis`): `lua cli.lua queue:work`, ou o
  serviço `worker` do Docker. Escale rodando mais processos.

Em desenvolvimento (`debug = true`) o worker recarrega os módulos `src.*` a
cada job, então editar um job não exige reiniciar nada.

### CLI (driver `redis`)

```bash
lua cli.lua queue:work [--queue=mail,default] [--once] [--sleep=1]
                       [--max-jobs=N] [--max-time=S] [--stop-when-empty]
lua cli.lua queue:status [fila]             # ready / delayed / reserved / failed
lua cli.lua queue:failed [fila] [--limit=20]
lua cli.lua queue:retry <id|all> [--queue=fila]
lua cli.lua queue:clear-failed [fila]
lua cli.lua cache:clear
```

Com o driver `shared` a fila vive na memória do servidor, que a CLI não
alcança. Os mesmos dados estão disponíveis no código via
`app.queue:size(name)`, `:failed(name)`, `:retry(name, id)` e
`:clear_failed(name)`.

## Docker

O `docker-compose.yml` traz os serviços `redis` (com AOF, senha via
`REDIS_PASSWORD`) e `worker` no profile `redis`. Eles ficam desligados até
você ligar o profile no `.env`:

```dotenv
COMPOSE_PROFILES=redis
CACHE_DRIVER=redis
QUEUE_DRIVER=redis
REDIS_PASSWORD=uma-senha-longa
```

O `lua cli.lua setup` pergunta "Use Redis for cache and queues?" e grava isso
para você. Depois, `lua cli.lua run` sobe app + MySQL + Redis + worker e
`docker compose logs -f worker` mostra os jobs em JSON. Dentro do compose,
`REDIS_HOST` aponta para o serviço `redis`; fora dele, use
`127.0.0.1:${REDIS_FORWARD_PORT:-6380}`.

Em produção, rode a mesma imagem com `command: ["bin/crescent", "queue:work"]`
para os workers e deixe `QUEUE_DRIVER=redis` em todos os containers.

## Redis direto

```lua
local redis = ctx.redis          -- ou require("crescent.redis").new(config.redis)
redis:command("hset", "k", "f", "v")
redis:eval("return redis.call('get', KEYS[1])", { "k" })
redis:with(function(red)          -- conexão do pool, para pipelines
    red:init_pipeline()
    red:incr("a"); red:incr("b")
    return red:commit_pipeline()
end)
```

## Testes

`config/test.lua` usa `queue.driver = "sync"`, então `push` executa o job na
hora e os erros aparecem no teste. Para testar contra um Redis real:

```bash
docker run -d --rm -p 127.0.0.1:6390:6379 redis:7.4-alpine
REDIS_TEST_HOST=127.0.0.1 REDIS_TEST_PORT=6390 lua cli.lua test redis-integration
```
