# 📚 Documentação do Crescent Framework

## Bem-vindo ao Crescent! 🌙

Este é o hub central da documentação. Navegue pelos links abaixo para encontrar o que precisa.

---

## 🚀 Começando

### Para Iniciantes
1. **[README.md](./README.md)** - Comece aqui! Visão geral completa do framework
2. **[QUICKSTART.md](./QUICKSTART.md)** - Guia passo a passo para começar rapidamente
3. **[example.lua](./example.lua)** - Exemplo básico de uso
4. **[test.lua](./test.lua)** - Execute para testar o framework

### Exemplos de Código
- **[main.lua](./main.lua)** - Aplicação principal
- **[example.lua](./example.lua)** - Exemplo básico com rotas simples
- **[advanced_example.lua](./advanced_example.lua)** - API completa com autenticação

---

## 📖 Documentação Técnica

### Arquitetura e Design
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Arquitetura detalhada com diagramas
  - Estrutura geral do sistema
  - Fluxo de requisições
  - Módulos e responsabilidades
  - Camadas de segurança
  - Pontos de extensibilidade

### Performance e Otimização
- **[PERFORMANCE.md](./PERFORMANCE.md)** - Guia completo de performance
  - Benchmarks e métricas
  - Otimizações recomendadas
  - Monitoramento e profiling
  - Estratégias de deployment
  - Tips de escalabilidade

### Histórico
- **[CHANGELOG.md](./CHANGELOG.md)** - Histórico de versões e mudanças

---

## 🏗️ Estrutura do Framework

### Módulos Core (`crescent/core/`)
- **[router.lua](./crescent/core/router.lua)** - Sistema de roteamento
- **[request.lua](./crescent/core/request.lua)** - Processamento de requisições
- **[response.lua](./crescent/core/response.lua)** - Utilitários de resposta
- **[context.lua](./crescent/core/context.lua)** - Context object (req/res wrapper)

### Middlewares (`crescent/middleware/`)
- **[cors.lua](./crescent/middleware/cors.lua)** - Configuração CORS
- **[security.lua](./crescent/middleware/security.lua)** - Segurança (rate limit, headers)
- **[auth.lua](./crescent/middleware/auth.lua)** - Autenticação (Bearer, Basic, API Key)
- **[logger.lua](./crescent/middleware/logger.lua)** - Logging de requisições

### Utilitários (`crescent/utils/`)
- **[string.lua](./crescent/utils/string.lua)** - Manipulação segura de strings
- **[path.lua](./crescent/utils/path.lua)** - Manipulação de paths HTTP
- **[headers.lua](./crescent/utils/headers.lua)** - Normalização de headers

### Servidor
- **[server.lua](./crescent/server.lua)** - Servidor HTTP principal
- **[init.lua](./crescent/init.lua)** - Ponto de entrada do framework

---

## ⚙️ Configuração

### Ambientes
- **[config/development.lua](./config/development.lua)** - Configuração de desenvolvimento
- **[config/production.lua](./config/production.lua)** - Configuração de produção

### Deploy
- **[config/nginx.conf](./config/nginx.conf)** - Configuração Nginx production-ready
- **[config/crescent.service](./config/crescent.service)** - Systemd service
- **[deploy.sh](./deploy.sh)** - Script de deploy automático

---

## 📋 Guias Rápidos

### Desenvolvimento Local

```bash
# 1. Testar o framework
luvit test.lua

# 2. Rodar exemplo básico
luvit example.lua

# 3. Rodar exemplo avançado
luvit advanced_example.lua
```

### Testando Endpoints

```bash
# Health check
curl http://localhost:8080/health

# Documentação
curl http://localhost:8080/docs

# Listagem de usuários
curl http://localhost:8080/api/users

# Rota protegida
curl http://localhost:8080/api/profile \
  -H "Authorization: Bearer user-token-456"
```

### Deploy em Produção

```bash
# Clone no servidor
git clone <repo> /var/www/crescent

# Execute deploy automático
cd /var/www/crescent
sudo ./deploy.sh

# Configure variáveis
sudo nano /etc/crescent/environment

# Reinicie o serviço
sudo systemctl restart crescent
```

---

## 🎯 Casos de Uso

### API RESTful Simples
- Veja: [example.lua](./example.lua)
- Rotas básicas com JSON
- CORS configurado
- Health check

### API Completa com Autenticação
- Veja: [advanced_example.lua](./advanced_example.lua)
- Autenticação Bearer Token
- Autorização por role
- CRUD completo
- Validação de dados

### Microserviço
- Use: [config/production.lua](./config/production.lua)
- Nginx como proxy
- Rate limiting
- Logs estruturados
- Health checks

---

## 🔍 Busca Rápida

### Preciso de...

#### ...rotas básicas
→ [README.md - Uso Básico](./README.md#-uso-básico)

#### ...autenticação
→ [README.md - Autenticação](./README.md#autenticação-bearer-token)  
→ [advanced_example.lua](./advanced_example.lua)

#### ...melhorar performance
→ [PERFORMANCE.md](./PERFORMANCE.md)  
→ [ARCHITECTURE.md - Performance](./ARCHITECTURE.md#-performance-considerations)

#### ...fazer deploy
→ [QUICKSTART.md - Deploy em Produção](./QUICKSTART.md#-deploy-em-produção)  
→ [deploy.sh](./deploy.sh)

#### ...segurança
→ [README.md - Checklist de Segurança](./README.md#-checklist-de-segurança-para-produção)  
→ [PERFORMANCE.md - Security Best Practices](./PERFORMANCE.md#-security-best-practices)

#### ...entender a arquitetura
→ [ARCHITECTURE.md](./ARCHITECTURE.md)

#### ...troubleshooting
→ [QUICKSTART.md - Troubleshooting](./QUICKSTART.md#-troubleshooting)

---

## 📊 Estatísticas

- **Módulos**: 13 arquivos Lua
- **Linhas de código**: ~2000
- **Tamanho**: ~50KB
- **Performance**: 15-20k req/s (standalone), 25-35k req/s (com Nginx)
- **Memória**: ~50MB
- **Latência**: <10ms (p99)

---

## 🆘 Suporte

### Problemas Comuns
- [QUICKSTART.md - Troubleshooting](./QUICKSTART.md#-troubleshooting)

### Como Contribuir
- [README.md - Contribuindo](./README.md#-contribuindo)

### Licença
- [LICENSE](./LICENSE) - MIT License

---

## 🎓 Recursos de Aprendizado

### Ordem Recomendada de Leitura

1. **[README.md](./README.md)** - Visão geral
2. **[QUICKSTART.md](./QUICKSTART.md)** - Setup inicial
3. **[example.lua](./example.lua)** - Código básico
4. **[advanced_example.lua](./advanced_example.lua)** - Recursos avançados
5. **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Entendimento profundo
6. **[PERFORMANCE.md](./PERFORMANCE.md)** - Otimização

### Para Diferentes Níveis

#### Iniciante
- README.md
- QUICKSTART.md
- example.lua

#### Intermediário
- advanced_example.lua
- ARCHITECTURE.md
- Módulos do crescent/

#### Avançado
- PERFORMANCE.md
- config/nginx.conf
- Código fonte completo

---

## 📱 Links Externos

- **Luvit**: https://luvit.io/
- **Nginx**: https://nginx.org/
- **Let's Encrypt**: https://letsencrypt.org/

---

## 🌙 Crescent Framework

**Versão**: 1.0.0  
**Desenvolvido por**: Tyne Forge Systems  
**Licença**: MIT  

Simple, Fast, Secure 🚀
