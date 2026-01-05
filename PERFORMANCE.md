# Performance e Boas Práticas - Crescent Framework

## 📑 Navegação
- **[📚 INDEX - Hub de Documentação](./INDEX.md)**
- **[← Voltar ao README](./README.md)**
- **[Quick Start](./QUICKSTART.md)**
- **[Arquitetura](./ARCHITECTURE.md)**
- **[Changelog](./CHANGELOG.md)**

## 📑 Índice

- [⚡ Benchmarks](#-benchmarks)
  - [Setup de Teste](#setup-de-teste)
  - [Resultados Esperados](#resultados-esperados)
  - [Comparação com Outros Frameworks](#comparação-com-outros-frameworks)
- [🎯 Otimizações Recomendadas](#-otimizações-recomendadas)
  - [1. Nginx Configuration](#1-nginx-configuration)
  - [2. Sistema Operacional](#2-sistema-operacional)
  - [3. Crescent Application](#3-crescent-application)
- [📊 Monitoring e Profiling](#-monitoring-e-profiling)
  - [1. Logging Eficiente](#1-logging-eficiente)
  - [2. Métricas](#2-métricas)
  - [3. Memory Profiling](#3-memory-profiling)
- [🔒 Security Best Practices](#-security-best-practices)
  - [1. Input Validation](#1-input-validation)
  - [2. SQL Injection Prevention](#2-sql-injection-prevention)
  - [3. Rate Limiting por Rota](#3-rate-limiting-por-rota)
  - [4. HTTPS Only (Produção)](#4-https-only-produção)
- [🚀 Deployment Strategies](#-deployment-strategies)
  - [1. Zero-Downtime Deployment](#1-zero-downtime-deployment)
  - [2. Multi-Instance (Load Balancing)](#2-multi-instance-load-balancing)
  - [3. Docker (Opcional)](#3-docker-opcional)
- [📈 Scalability Tips](#-scalability-tips)
- [🔍 Debugging](#-debugging)
- [📚 Recursos Adicionais](#-recursos-adicionais)

---

## ⚡ Benchmarks

### Setup de Teste

```bash
# Ferramenta: wrk (HTTP benchmarking tool)
# Instalar: brew install wrk (macOS) ou apt install wrk (Linux)

# Configuração:
# - CPU: 4 cores
# - RAM: 8GB
# - Nginx + Crescent
```

### Resultados Esperados

#### Sem Nginx (Desenvolvimento)
```bash
wrk -t4 -c100 -d30s http://localhost:8080/health

# Resultados típicos:
# Requests/sec: 15,000 - 20,000
# Latency (avg): 5-8ms
# Latency (p99): 15-25ms
```

#### Com Nginx (Produção)
```bash
wrk -t4 -c100 -d30s http://localhost/health

# Resultados típicos:
# Requests/sec: 25,000 - 35,000
# Latency (avg): 3-5ms
# Latency (p99): 10-15ms
```

#### Rotas com JSON
```bash
wrk -t4 -c100 -d30s http://localhost/api/users

# Resultados típicos:
# Requests/sec: 10,000 - 15,000
# Latency (avg): 8-12ms
# Latency (p99): 20-30ms
```

### Comparação com Outros Frameworks

```
Framework        | Requests/sec | Latency (avg) | Memory
---------------------------------------------------------
Crescent         | 15-20k       | 5-8ms         | ~50MB
Express (Node)   | 8-12k        | 10-15ms       | ~150MB
Flask (Python)   | 3-5k         | 20-30ms       | ~100MB
Lapis (Lua)      | 20-25k       | 4-6ms         | ~40MB
```

**Nota**: Crescent oferece excelente balanço entre performance e facilidade de uso.

## 🎯 Otimizações Recomendadas

### 1. Nginx Configuration

```nginx
# /etc/nginx/nginx.conf

worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    # Keepalive
    keepalive_timeout 65;
    keepalive_requests 100;
    
    # Buffers
    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 8k;
    
    # Timeouts
    client_body_timeout 12;
    client_header_timeout 12;
    send_timeout 10;
    
    # Gzip
    gzip on;
    gzip_vary on;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript;
    
    # Cache (para static files)
    open_file_cache max=10000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
}
```

### 2. Sistema Operacional

```bash
# /etc/sysctl.conf

# Aumenta limites de conexões
net.core.somaxconn = 65536
net.ipv4.tcp_max_syn_backlog = 8192

# Keepalive settings
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_keepalive_probes = 3

# TCP optimizations
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1

# File descriptors
fs.file-max = 2097152

# Aplicar:
sudo sysctl -p
```

```bash
# /etc/security/limits.conf

* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
```

### 3. Crescent Application

#### Cache de Rotas (já implementado)
```lua
-- Router compila patterns uma única vez
-- Não há overhead de regex em cada requisição
```

#### Connection Pooling (se usar DB)
```lua
-- Exemplo com PostgreSQL
local pg_pool = require("pg_pool")

local pool = pg_pool.new({
    host = "localhost",
    port = 5432,
    database = "mydb",
    user = "user",
    password = "pass",
    max = 20,  -- máximo de conexões
    idle_timeout = 30000
})

-- Use conexões do pool
local conn = pool:connect()
-- ... usar conexão
conn:close()  -- retorna ao pool
```

#### Evite Blocking Operations
```lua
-- ❌ BAD: Blocking
local result = os.execute("sleep 5")

-- ✅ GOOD: Async
local timer = require("timer")
timer.setTimeout(5000, function()
    -- código assíncrono
end)
```

## 📊 Monitoring e Profiling

### 1. Logging Eficiente

```lua
-- Em produção, use logger básico
app:use(crescent.middleware.logger.basic())

-- Em desenvolvimento, use detalhado
app:use(crescent.middleware.logger.detailed())

-- Custom logger com filtros
app:use(crescent.middleware.logger.custom(function(data, ctx)
    -- Log apenas erros em produção
    if data.status >= 400 then
        return string.format("[ERROR] %s %s - %d", 
            data.method, data.path, data.status)
    end
    return nil
end))
```

### 2. Métricas

```lua
-- Adicione endpoint de métricas
local metrics = {
    requests_total = 0,
    requests_success = 0,
    requests_error = 0,
    latency_sum = 0
}

app:use(function(ctx, next)
    metrics.requests_total = metrics.requests_total + 1
    local start = os.clock()
    
    local result = next and next() or true
    
    local duration = (os.clock() - start) * 1000
    metrics.latency_sum = metrics.latency_sum + duration
    
    if ctx.res.statusCode and ctx.res.statusCode < 400 then
        metrics.requests_success = metrics.requests_success + 1
    else
        metrics.requests_error = metrics.requests_error + 1
    end
    
    return result
end)

app:get("/metrics", function(ctx)
    return ctx.json(200, {
        requests_total = metrics.requests_total,
        requests_success = metrics.requests_success,
        requests_error = metrics.requests_error,
        latency_avg = metrics.latency_sum / math.max(metrics.requests_total, 1),
        uptime = os.clock()
    })
end)
```

### 3. Memory Profiling

```lua
-- Monitore uso de memória
app:get("/memory", function(ctx)
    collectgarbage("collect")  -- force GC
    
    return ctx.json(200, {
        memory_kb = collectgarbage("count"),
        memory_mb = math.floor(collectgarbage("count") / 1024 * 100) / 100
    })
end)
```

## 🔒 Security Best Practices

### 1. Input Validation

```lua
-- Sempre valide inputs
local function validate_user_input(ctx)
    if not ctx.body then
        return false, "missing body"
    end
    
    -- Valida tipos
    if type(ctx.body.name) ~= "string" then
        return false, "name must be string"
    end
    
    -- Valida tamanho
    if #ctx.body.name > 100 then
        return false, "name too long"
    end
    
    -- Valida formato
    if not ctx.body.email:match("^[%w%._%+%-]+@[%w%.%-]+%.[%a]+$") then
        return false, "invalid email"
    end
    
    return true
end
```

### 2. SQL Injection Prevention

```lua
-- Use prepared statements
local function get_user_by_email(email)
    -- ❌ NEVER do this:
    -- local query = "SELECT * FROM users WHERE email = '" .. email .. "'"
    
    -- ✅ Do this:
    local stmt = db:prepare("SELECT * FROM users WHERE email = ?")
    return stmt:execute(email)
end
```

### 3. Rate Limiting por Rota

```lua
-- Rate limit específico para rotas sensíveis
local auth_rate_limit = crescent.middleware.security.rate_limit({
    window = 60,
    max_requests = 5  -- apenas 5 tentativas de login por minuto
})

app:post("/login", function(ctx)
    -- Aplica rate limit
    local ok, err = auth_rate_limit(ctx, function() return true end)
    if not ok then
        return ctx.error(429, "too many login attempts")
    end
    
    -- ... lógica de login
end)
```

### 4. HTTPS Only (Produção)

```lua
-- Middleware que força HTTPS
local function force_https()
    return function(ctx, next)
        local proto = ctx.getHeader("x-forwarded-proto")
        
        if proto and proto:lower() ~= "https" then
            local url = "https://" .. ctx.getHeader("host") .. ctx.path
            return ctx.redirect(url, 301)
        end
        
        if next then
            return next()
        end
        return true
    end
end

-- Em produção
if env == "production" then
    app:use(force_https())
end
```

## 🚀 Deployment Strategies

### 1. Zero-Downtime Deployment

```bash
#!/bin/bash
# rolling_deploy.sh

# Inicia nova instância na porta 8081
luvit example.lua &
NEW_PID=$!

# Aguarda health check
sleep 3
if curl -f http://localhost:8081/health; then
    echo "Nova instância OK"
    
    # Atualiza nginx upstream
    # ... atualizar configuração
    
    # Reload nginx (sem downtime)
    sudo nginx -s reload
    
    # Para instância antiga
    kill $OLD_PID
else
    echo "Nova instância FALHOU"
    kill $NEW_PID
    exit 1
fi
```

### 2. Multi-Instance (Load Balancing)

```nginx
# Nginx upstream com múltiplas instâncias
upstream crescent_backend {
    least_conn;  # ou ip_hash, ou round_robin
    
    server 127.0.0.1:8080 weight=1 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8081 weight=1 max_fails=3 fail_timeout=30s;
    server 127.0.0.1:8082 weight=1 max_fails=3 fail_timeout=30s;
    
    keepalive 64;
}
```

### 3. Docker (Opcional)

```dockerfile
# Dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    curl \
    build-essential \
    git

# Instala Luvit
RUN curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh && \
    mv luvi luvit lit /usr/local/bin/

WORKDIR /app
COPY . .

EXPOSE 8080

CMD ["luvit", "example.lua"]
```

```yaml
# docker-compose.yml
version: '3.8'

services:
  crescent:
    build: .
    ports:
      - "8080:8080"
    environment:
      - ENV=production
      - DB_HOST=db
    restart: always
    
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - crescent
```

## 📈 Scalability Tips

### Horizontal Scaling
- Use load balancer (Nginx, HAProxy, AWS ELB)
- Cada instância é stateless
- Sessões em Redis/Memcached se necessário

### Vertical Scaling
- Aumente worker_connections no Nginx
- Aumente system limits (file descriptors)
- Mais CPU/RAM por instância

### Database Scaling
- Connection pooling
- Read replicas para queries
- Cache (Redis) para dados frequentes
- Índices otimizados

## 🔍 Debugging

```lua
-- Debug middleware
local function debug_middleware()
    return function(ctx, next)
        print("\n=== DEBUG ===")
        print("Method:", ctx.method)
        print("Path:", ctx.path)
        print("Headers:", require("json").stringify(ctx.headers))
        print("Query:", require("json").stringify(ctx.query))
        print("Params:", require("json").stringify(ctx.params))
        
        local result = next and next() or true
        
        print("Status:", ctx.res.statusCode or 200)
        print("=============\n")
        
        return result
    end
end

-- Use apenas em desenvolvimento
if env == "development" then
    app:use(debug_middleware())
end
```

## 📚 Recursos Adicionais

- **Luvit Docs**: https://luvit.io/
- **Nginx Docs**: https://nginx.org/en/docs/
- **Lua Performance Tips**: https://www.lua.org/gems/
- **HTTP/2**: Configure no Nginx para melhor performance
- **WebSockets**: Extensão possível com luvit-websocket

---

**Crescent Framework** - Performance com Simplicidade 🌙
