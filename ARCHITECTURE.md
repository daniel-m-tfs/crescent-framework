# Arquitetura do Crescent Framework

## 📑 Navegação
- **[📚 INDEX - Hub de Documentação](./INDEX.md)**
- **[← Voltar ao README](./README.md)**
- **[Quick Start](./QUICKSTART.md)**
- **[Performance](./PERFORMANCE.md)**
- **[Changelog](./CHANGELOG.md)**

## 📑 Índice

- [📐 Estrutura Geral](#-estrutura-geral)
- [🔄 Fluxo de Requisição](#-fluxo-de-requisição)
  - [Detalhamento do Fluxo](#detalhamento-do-fluxo)
- [🧩 Módulos e Responsabilidades](#-módulos-e-responsabilidades)
  - [Core (`crescent/core/`)](#core-crescentcore)
  - [Middleware (`crescent/middleware/`)](#middleware-crescentmiddleware)
  - [Utils (`crescent/utils/`)](#utils-crescentutils)
- [🔐 Camadas de Segurança](#-camadas-de-segurança)
- [⚡ Performance Considerations](#-performance-considerations)
- [🔌 Extensibilidade](#-extensibilidade)
  - [Custom Middleware](#custom-middleware)
  - [Custom Response Types](#custom-response-types)
  - [Custom Validators](#custom-validators)
- [📊 Monitoring Points](#-monitoring-points)

---

## �📐 Estrutura Geral

```
┌─────────────────────────────────────────────────────────┐
│                     NGINX (Porta 80/443)                │
│  - SSL/TLS Termination                                  │
│  - Rate Limiting                                        │
│  - Static Files                                         │
│  - Gzip Compression                                     │
│  - Load Balancing (opcional)                            │
└────────────────────┬────────────────────────────────────┘
                     │ Proxy Pass
                     ▼
┌─────────────────────────────────────────────────────────┐
│              Crescent App (Porta 8080)                  │
│                                                         │
│  ┌─────────────────────────────────────────┐           │
│  │         crescent/server.lua              │           │
│  │  - Request Handler                       │           │
│  │  - Middleware Pipeline                   │           │
│  │  - Error Handler                         │           │
│  └──────────────┬──────────────────────────┘           │
│                 │                                        │
│  ┌──────────────▼───────────────────────────┐           │
│  │        Middleware Layer                   │           │
│  │  1. Logger (basic/detailed)              │           │
│  │  2. CORS (default/strict)                │           │
│  │  3. Security Headers                     │           │
│  │  4. Rate Limiting                        │           │
│  │  5. Path Traversal Protection            │           │
│  │  6. Body Size Limit                      │           │
│  │  7. Auth (Bearer/Basic/API Key)          │           │
│  └──────────────┬───────────────────────────┘           │
│                 │                                        │
│  ┌──────────────▼───────────────────────────┐           │
│  │         crescent/core/router.lua         │           │
│  │  - Route Matching                        │           │
│  │  - Path Compilation                      │           │
│  │  - Parameter Extraction                  │           │
│  └──────────────┬───────────────────────────┘           │
│                 │                                        │
│  ┌──────────────▼───────────────────────────┐           │
│  │        crescent/core/context.lua         │           │
│  │  - Request/Response Wrapper              │           │
│  │  - Helper Methods                        │           │
│  │  - State Management                      │           │
│  └──────────────┬───────────────────────────┘           │
│                 │                                        │
│  ┌──────────────▼───────────────────────────┐           │
│  │          Route Handler                    │           │
│  │  - Business Logic                        │           │
│  │  - Database Access                       │           │
│  │  - Response Generation                   │           │
│  └──────────────┬───────────────────────────┘           │
│                 │                                        │
│  ┌──────────────▼───────────────────────────┐           │
│  │       crescent/core/response.lua         │           │
│  │  - JSON Response                         │           │
│  │  - Text Response                         │           │
│  │  - Error Response                        │           │
│  │  - Security Headers                      │           │
│  └──────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────┘
```

## 🔄 Fluxo de Requisição

```
Cliente → Nginx → Crescent → Handler → Response
  │        │         │          │          │
  │        │         │          │          └─→ JSON/Text
  │        │         │          └─────────────→ DB/API
  │        │         └────────────────────────→ Middleware
  │        └──────────────────────────────────→ Proxy
  └───────────────────────────────────────────→ HTTP Request
```

### Detalhamento do Fluxo

1. **Cliente faz requisição**
   - Browser/App/API client envia HTTP request

2. **Nginx recebe (Porta 80/443)**
   - Termina SSL/TLS
   - Aplica rate limiting (primeira camada)
   - Compressão Gzip
   - Logs de acesso
   - Proxy para Crescent

3. **Crescent recebe (Porta 8080)**
   - `server.lua` cria context
   - Normaliza headers
   - Parse URL e query params

4. **Middleware Pipeline**
   - Executados em ordem (chain of responsibility)
   - Qualquer middleware pode interromper a cadeia
   - Logger registra início da requisição

5. **Router**
   - Match de rota com pattern
   - Extração de parâmetros de rota
   - Se não encontrar rota → 404 handler

6. **Body Reading (se necessário)**
   - Lê body de forma assíncrona
   - Valida tamanho (DoS protection)
   - Parse JSON se Content-Type aplicável

7. **Handler Execution**
   - Recebe context com todos os dados
   - Executa lógica de negócio
   - Retorna response ou usa ctx helpers

8. **Response**
   - Serializa dados (JSON)
   - Define headers apropriados
   - Envia ao cliente via Nginx

## 🧩 Módulos e Responsabilidades

### Core (`crescent/core/`)

#### `router.lua`
- Compilação de rotas em patterns Lua
- Matching de URLs com rotas registradas
- Extração de parâmetros dinâmicos
- Gerenciamento de prefixos e grupos

#### `request.lua`
- Leitura assíncrona do body
- Validação de Content-Type
- Validação de Content-Length
- Proteção contra DoS (body muito grande)

#### `response.lua`
- Helpers para JSON, Text, HTML
- Gerenciamento de headers
- Headers de segurança
- CORS headers

#### `context.lua`
- Wrapper unificado de req/res
- Normalização de headers
- State management (compartilhado entre middlewares)
- Helper methods convenientes

### Middleware (`crescent/middleware/`)

#### `cors.lua`
- CORS permissivo (desenvolvimento)
- CORS restritivo (produção)
- Preflight handling (OPTIONS)

#### `security.lua`
- Headers de segurança padrão
- Rate limiting em memória
- Validação de body size
- Proteção path traversal
- Validação de métodos HTTP

#### `auth.lua`
- Bearer token authentication
- Basic authentication
- API Key authentication
- Validação customizável

#### `logger.lua`
- Logger básico (método, path, status)
- Logger detalhado (headers, params, timing)
- Logger customizado (formato livre)

### Utils (`crescent/utils/`)

#### `string.lua`
- Escape de patterns Lua (segurança)
- Trim de strings
- Validação de strings seguras
- Sanitização
- Limitação de tamanho

#### `path.lua`
- Join de paths
- Compilação de templates
- Validação de segurança
- Normalização

#### `headers.lua`
- Normalização multi-formato
- Extração de Bearer token
- Validação de injeção

## 🔐 Camadas de Segurança

```
┌─────────────────────────────────────────────────┐
│  Layer 1: Nginx                                 │
│  - Rate Limiting (IP-based)                     │
│  - SSL/TLS                                      │
│  - Request Size Limit                           │
│  - DDoS Protection (connection limit)           │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Layer 2: Middleware (Global)                   │
│  - Security Headers (XSS, CSP, etc)            │
│  - Path Traversal Protection                    │
│  - Body Size Validation                         │
│  - Rate Limiting (Application-level)            │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Layer 3: Router                                │
│  - Path Validation                              │
│  - Pattern Escape                               │
│  - Parameter Extraction                         │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Layer 4: Authentication                        │
│  - Token Validation                             │
│  - User Authorization                           │
│  - Role-Based Access                            │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│  Layer 5: Handler                               │
│  - Input Validation                             │
│  - Business Logic                               │
│  - Data Sanitization                            │
└─────────────────────────────────────────────────┘
```

## ⚡ Performance Considerations

### 1. **Nginx Cache**
```
- Static files servidos diretamente
- Proxy cache para respostas frequentes
- Gzip compression
```

### 2. **Keepalive Connections**
```
- Nginx ↔ Crescent: keepalive 64
- Reduz overhead de TCP handshake
- Melhor throughput
```

### 3. **Async I/O**
```
- Body reading é assíncrono
- Non-blocking event loop (Luvit)
- Múltiplas requisições simultâneas
```

### 4. **Route Caching**
```
- Patterns compilados uma vez
- Matching eficiente com patterns Lua
- Sem regex pesado
```

### 5. **Memory Management**
```
- Body size limitado
- Rate limiting previne abusos
- Sem memory leaks (GC do Lua)
```

## 🔌 Extensibilidade

### Custom Middleware

```lua
local function my_middleware()
    return function(ctx, next)
        -- Lógica antes
        local result = next()
        -- Lógica depois
        return result
    end
end

app:use(my_middleware())
```

### Custom Response Types

```lua
local response = require("crescent.core.response")

function response.xml(res, status, xml)
    res:setHeader("Content-Type", "application/xml")
    res:writeHead(status or 200)
    res:finish(xml)
end
```

### Custom Validators

```lua
local auth = crescent.middleware.auth.bearer(function(token, ctx)
    -- Custom validation logic
    local user = validate_jwt(token)
    if user then
        return true, user
    end
    return false, "invalid token"
end)
```

## 📊 Monitoring Points

1. **Nginx Logs**
   - Access logs
   - Error logs
   - Rate limit hits

2. **Application Logs**
   - Request/Response (via middleware)
   - Error logs
   - Performance metrics

3. **System Metrics**
   - CPU usage
   - Memory usage
   - Network I/O
   - Disk I/O

4. **Health Checks**
   - `/health` endpoint
   - Database connectivity
   - External services

---

Esta arquitetura prioriza **performance**, **segurança** e **manutenibilidade**.
