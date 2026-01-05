# Crescent Framework 🌙

Framework HTTP minimalista e performático para Luvit, com foco em segurança e simplicidade.

> 📚 **[Ver Índice Completo da Documentação](./INDEX.md)** - Hub central com todos os recursos

## 📑 Índice

### Documentação
- **[📚 INDEX - Hub de Documentação](./INDEX.md)** - Navegação completa
- **[Quick Start Guide](./QUICKSTART.md)** - Guia rápido para começar
- **[Architecture](./ARCHITECTURE.md)** - Arquitetura detalhada e diagramas
- **[Performance Guide](./PERFORMANCE.md)** - Benchmarks e otimizações
- **[Changelog](./CHANGELOG.md)** - Histórico de versões

### Neste Documento
- [🚀 Características](#-características)
- [📦 Estrutura do Projeto](#-estrutura-do-projeto)
- [🔧 Instalação](#-instalação)
  - [Requisitos](#requisitos)
  - [Setup](#setup)
- [📖 Uso Básico](#-uso-básico)
- [🛡️ Segurança](#️-segurança)
  - [Headers de Segurança](#headers-de-segurança)
  - [Rate Limiting](#rate-limiting)
  - [Autenticação Bearer Token](#autenticação-bearer-token)
- [🔀 Roteamento Avançado](#-roteamento-avançado)
  - [Grupos de Rotas](#grupos-de-rotas)
  - [Parâmetros de Rota](#parâmetros-de-rota)
- [🌐 Deploy com Nginx](#-deploy-com-nginx-recomendado-para-produção)
  - [Configuração Nginx](#configuração-nginx)
  - [Systemd Service](#systemd-service)
- [⚡ Performance Tips](#-performance-tips)
- [🔒 Checklist de Segurança](#-checklist-de-segurança-para-produção)
- [📝 Variáveis de Ambiente](#-variáveis-de-ambiente)
- [🤝 Contribuindo](#-contribuindo)
- [📄 Licença](#-licença)
- [🙏 Créditos](#-créditos)

---

## �🚀 Características

- **Modular**: Arquitetura organizada em módulos independentes
- **Performático**: Código otimizado com foco em performance
- **Seguro**: Middlewares de segurança integrados (rate limiting, headers, validações)
- **Flexível**: Sistema de middlewares e roteamento avançado
- **Tipado**: Estrutura clara e bem documentada

## 📦 Estrutura do Projeto

```
crescent/
├── init.lua                 # Ponto de entrada principal
├── server.lua              # Servidor HTTP
├── core/                   # Funcionalidades principais
│   ├── router.lua          # Sistema de roteamento
│   ├── request.lua         # Processamento de requisições
│   ├── response.lua        # Utilitários de resposta
│   └── context.lua         # Context object (req/res)
├── middleware/             # Middlewares prontos
│   ├── cors.lua            # Configuração CORS
│   ├── security.lua        # Segurança (rate limit, headers, etc)
│   ├── auth.lua            # Autenticação (Bearer, Basic, API Key)
│   └── logger.lua          # Logging de requisições
└── utils/                  # Utilitários
    ├── string.lua          # Manipulação de strings
    ├── path.lua            # Manipulação de paths
    └── headers.lua         # Manipulação de headers

config/
├── development.lua         # Configuração de dev
└── production.lua          # Configuração de produção
```

## 🔧 Instalação

### Requisitos

- [Luvit](https://luvit.io/) instalado

### Setup

```bash
# Clone o repositório
git clone <repo-url>
cd lua_api

# Execute o exemplo
ENV=development luvit example.lua
```

## 📖 Uso Básico

```lua
local crescent = require("crescent")

-- Cria aplicação
local app = crescent.new()

-- Middleware de logging
app:use(crescent.middleware.logger.basic())

-- Middleware CORS
app:use(crescent.middleware.cors.default())

-- Rota GET simples
app:get("/", function(ctx)
    return ctx.json(200, {
        message = "Hello, Crescent!"
    })
end)

-- Rota com parâmetros
app:get("/user/{id}", function(ctx)
    return ctx.json(200, {
        id = ctx.params.id
    })
end)

-- Rota POST com body
app:post("/user", function(ctx)
    local data = ctx.body
    return ctx.json(201, data)
end)

-- Inicia servidor
app:listen(8080, "0.0.0.0")
```

## 🛡️ Segurança

### Headers de Segurança

```lua
app:use(crescent.middleware.security.headers())
```

Adiciona automaticamente:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Strict-Transport-Security`

### Rate Limiting

```lua
app:use(crescent.middleware.security.rate_limit({
    window = 60,        -- 60 segundos
    max_requests = 100  -- 100 requisições
}))
```

### Autenticação Bearer Token

```lua
local auth = crescent.middleware.auth.bearer(function(token, ctx)
    if is_valid_token(token) then
        return true, {user_id = 123}
    end
    return false, "invalid token"
end)

app:get("/protected", auth, function(ctx)
    local user = ctx.state.user
    return ctx.json(200, {user = user})
end)
```

## 🔀 Roteamento Avançado

### Grupos de Rotas

```lua
app:group("/api/v1", function(app)
    app:get("/users", handler)
    app:post("/users", handler)
    
    app:group("/admin", function(app)
        app:get("/stats", handler)
    end)
end)

-- Resulta em:
-- GET  /api/v1/users
-- POST /api/v1/users
-- GET  /api/v1/admin/stats
```

### Parâmetros de Rota

```lua
-- Parâmetro obrigatório
app:get("/user/{id}", function(ctx)
    local id = ctx.params.id
end)

-- Parâmetro opcional (último segmento)
app:get("/user/{id}/posts/{post_id}", function(ctx)
    -- post_id é opcional
    local id = ctx.params.id
    local post_id = ctx.params.post_id -- pode ser nil
end)
```

## 🌐 Deploy com Nginx (Recomendado para Produção)

### Configuração Nginx

```nginx
upstream crescent_app {
    server 127.0.0.1:8080;
    keepalive 64;
}

server {
    listen 80;
    server_name yourdomain.com;
    
    # SSL (recomendado)
    listen 443 ssl http2;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    # Segurança
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Logs
    access_log /var/log/nginx/crescent_access.log;
    error_log /var/log/nginx/crescent_error.log;
    
    # Proxy para Crescent
    location / {
        proxy_pass http://crescent_app;
        proxy_http_version 1.1;
        
        # Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    
    location /api/ {
        limit_req zone=api_limit burst=20 nodelay;
        proxy_pass http://crescent_app;
    }
}
```

### Systemd Service

```ini
[Unit]
Description=Crescent Framework Application
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/path/to/lua_api
Environment="ENV=production"
ExecStart=/usr/local/bin/luvit example.lua
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Ative o service:

```bash
sudo systemctl enable crescent
sudo systemctl start crescent
sudo systemctl status crescent
```

## ⚡ Performance Tips

1. **Use Nginx/Apache na frente**: Melhor para servir assets estáticos e SSL
2. **Configure keepalive**: Reduz overhead de conexões
3. **Limite tamanho do body**: Protege contra DoS
4. **Use rate limiting**: No Nginx e/ou na aplicação
5. **Cache de rotas**: O framework já faz isso internamente
6. **Minimize middlewares**: Apenas os necessários
7. **Log assíncrono**: Em produção, use nível "basic"

## 🔒 Checklist de Segurança para Produção

- [ ] Usar HTTPS (SSL/TLS) via Nginx
- [ ] Configurar CORS corretamente (origins específicas)
- [ ] Ativar rate limiting
- [ ] Validar todos os inputs
- [ ] Limitar tamanho do body
- [ ] Usar headers de segurança
- [ ] Não expor stack traces em produção
- [ ] Usar variáveis de ambiente para secrets
- [ ] Implementar autenticação robusta
- [ ] Fazer sanitização de inputs
- [ ] Logs adequados (sem dados sensíveis)
- [ ] Atualizar dependências regularmente

## 📝 Variáveis de Ambiente

```bash
# Ambiente (development | production)
export ENV=production

# Database (exemplo)
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=myapp
export DB_USER=myuser
export DB_PASSWORD=mypassword

# Secrets
export JWT_SECRET=your-secret-key
export API_KEY=your-api-key
```

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o projeto
2. Crie sua feature branch (`git checkout -b feature/amazing`)
3. Commit suas mudanças (`git commit -m 'Add amazing feature'`)
4. Push para a branch (`git push origin feature/amazing`)
5. Abra um Pull Request

## 📄 Licença

MIT License - veja LICENSE para detalhes.

## 🙏 Créditos

Desenvolvido com ❤️ usando [Luvit](https://luvit.io/)

---

**Crescent Framework** - Simples, Rápido e Seguro 🌙
