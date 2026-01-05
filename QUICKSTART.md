# Guia de Início Rápido - Crescent Framework

## 📑 Navegação
- **[📚 INDEX - Hub de Documentação](./INDEX.md)**
- **[← Voltar ao README](./README.md)**
- **[Arquitetura](./ARCHITECTURE.md)**
- **[Performance](./PERFORMANCE.md)**
- **[Changelog](./CHANGELOG.md)**

## 📑 Índice

### Desenvolvimento
- [🚀 Desenvolvimento Local](#-desenvolvimento-local)
  - [1. Instalação do Luvit](#1-instalação-do-luvit)
  - [2. Clone/Configure o Projeto](#2-cloneconfigure-o-projeto)
  - [3. Execute os Testes](#3-execute-os-testes)
  - [4. Execute o Servidor de Desenvolvimento](#4-execute-o-servidor-de-desenvolvimento)
  - [5. Teste as Rotas](#5-teste-as-rotas)

### Produção
- [📦 Deploy em Produção](#-deploy-em-produção)
  - [1. Preparação do Servidor](#1-preparação-do-servidor)
  - [2. Configure SSL (Let's Encrypt)](#2-configure-ssl-lets-encrypt)
  - [3. Execute o Deploy](#3-execute-o-deploy)
  - [4. Configure Variáveis de Ambiente](#4-configure-variáveis-de-ambiente)
  - [5. Configure o Nginx](#5-configure-o-nginx)
  - [6. Verifique Status](#6-verifique-status)

### Manutenção
- [🔧 Comandos Úteis](#-comandos-úteis)
  - [Gerenciamento do Serviço](#gerenciamento-do-serviço)
  - [Nginx](#nginx)
- [🐛 Troubleshooting](#-troubleshooting)
- [📊 Monitoramento](#-monitoramento)
- [🔒 Segurança](#-segurança)
- [📈 Otimização](#-otimização)

---

## �🚀 Desenvolvimento Local

### 1. Instalação do Luvit

```bash
# macOS com Homebrew
brew install luvit

# Linux (Debian/Ubuntu)
curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh
```

### 2. Clone/Configure o Projeto

```bash
cd /Volumes/ssd/Tyne\ Forge\ Systems/lua_api

# Torne o script de deploy executável
chmod +x deploy.sh
```

### 3. Execute os Testes

```bash
luvit test.lua
```

### 4. Execute o Servidor de Desenvolvimento

```bash
ENV=development luvit example.lua
```

O servidor estará disponível em `http://localhost:8080`

### 5. Teste as Rotas

```bash
# Health check
curl http://localhost:8080/health

# Rota raiz
curl http://localhost:8080/

# Rota com parâmetro
curl http://localhost:8080/user/123

# POST com JSON
curl -X POST http://localhost:8080/user \
  -H "Content-Type: application/json" \
  -d '{"name":"John","email":"john@example.com"}'

# Rota protegida (sem token - deve retornar 401)
curl http://localhost:8080/api/profile

# Rota protegida (com token)
curl http://localhost:8080/api/profile \
  -H "Authorization: Bearer secret-token-123"
```

## 📦 Deploy em Produção

### 1. Preparação do Servidor

```bash
# Instale dependências
sudo apt update
sudo apt install -y nginx git curl build-essential

# Instale Luvit
curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh
sudo mv luvi luvit lit /usr/local/bin/
```

### 2. Configure SSL (Let's Encrypt)

```bash
# Instale certbot
sudo apt install -y certbot python3-certbot-nginx

# Obtenha certificado
sudo certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

### 3. Execute o Deploy

```bash
# Clone o repositório no servidor
git clone <seu-repo> /var/www/crescent

# Execute o script de deploy
cd /var/www/crescent
sudo ./deploy.sh
```

### 4. Configure Variáveis de Ambiente

```bash
# Edite o arquivo de ambiente
sudo nano /etc/crescent/environment

# Altere os valores:
ENV=production
DB_HOST=seu-host
DB_PASSWORD=senha-segura
JWT_SECRET=chave-secreta-jwt
API_KEY=sua-api-key

# Reinicie o serviço
sudo systemctl restart crescent
```

### 5. Configure o Nginx

```bash
# Edite a configuração do Nginx
sudo nano /etc/nginx/sites-available/crescent

# Altere:
# - server_name (seu domínio)
# - ssl_certificate (caminho para seu certificado)
# - ssl_certificate_key (caminho para sua chave)

# Teste a configuração
sudo nginx -t

# Reload do Nginx
sudo systemctl reload nginx
```

### 6. Verifique Status

```bash
# Status do serviço Crescent
sudo systemctl status crescent

# Logs em tempo real
sudo journalctl -u crescent -f

# Status do Nginx
sudo systemctl status nginx

# Teste o endpoint
curl https://yourdomain.com/health
```

## 🔧 Comandos Úteis

### Gerenciamento do Serviço

```bash
# Iniciar
sudo systemctl start crescent

# Parar
sudo systemctl stop crescent

# Reiniciar
sudo systemctl restart crescent

# Ver logs
sudo journalctl -u crescent -n 100

# Logs em tempo real
sudo journalctl -u crescent -f
```

### Nginx

```bash
# Testar configuração
sudo nginx -t

# Reload (sem downtime)
sudo systemctl reload nginx

# Restart
sudo systemctl restart nginx

# Ver logs de acesso
sudo tail -f /var/log/nginx/crescent_access.log

# Ver logs de erro
sudo tail -f /var/log/nginx/crescent_error.log
```

## 🐛 Troubleshooting

### Serviço não inicia

```bash
# Ver logs detalhados
sudo journalctl -u crescent -n 50

# Verificar permissões
sudo chown -R www-data:www-data /var/www/crescent

# Testar manualmente
cd /var/www/crescent
ENV=production luvit example.lua
```

### Nginx retorna 502 Bad Gateway

```bash
# Verifique se o serviço Crescent está rodando
sudo systemctl status crescent

# Verifique se está escutando na porta correta
sudo netstat -tlnp | grep 8080

# Verifique logs do Nginx
sudo tail -f /var/log/nginx/crescent_error.log
```

### Alta latência

```bash
# Verifique recursos do sistema
htop

# Logs de performance
sudo journalctl -u crescent -f

# Ajuste keepalive do Nginx
# Edite /etc/nginx/sites-available/crescent
# Aumente keepalive_timeout e keepalive em upstream
```

## 📊 Monitoramento

### Logs

```bash
# Análise de logs de acesso
sudo cat /var/log/nginx/crescent_access.log | \
  awk '{print $9}' | sort | uniq -c | sort -rn

# Top 10 IPs
sudo cat /var/log/nginx/crescent_access.log | \
  awk '{print $1}' | sort | uniq -c | sort -rn | head -10

# Requisições por hora
sudo cat /var/log/nginx/crescent_access.log | \
  awk '{print $4}' | cut -d: -f2 | sort | uniq -c
```

### Health Check

```bash
# Crie um script de monitoramento
cat > /usr/local/bin/crescent-health << 'EOF'
#!/bin/bash
if curl -f -s http://localhost:8080/health > /dev/null; then
    echo "OK"
    exit 0
else
    echo "FAIL"
    exit 1
fi
EOF

sudo chmod +x /usr/local/bin/crescent-health

# Configure cron para verificar a cada 5 minutos
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/crescent-health || systemctl restart crescent") | crontab -
```

## 🔒 Segurança

### Firewall (UFW)

```bash
# Ative UFW
sudo ufw enable

# Permita SSH
sudo ufw allow 22

# Permita HTTP/HTTPS
sudo ufw allow 80
sudo ufw allow 443

# Verifique status
sudo ufw status
```

### Fail2Ban

```bash
# Instale
sudo apt install -y fail2ban

# Configure para Nginx
sudo nano /etc/fail2ban/jail.local

# Adicione:
[nginx-http-auth]
enabled = true

[nginx-noscript]
enabled = true

[nginx-badbots]
enabled = true

# Reinicie
sudo systemctl restart fail2ban
```

## 📈 Otimização

### Nginx

```bash
# Ajuste worker_processes em /etc/nginx/nginx.conf
worker_processes auto;
worker_connections 1024;

# Ative cache
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m;
```

### Sistema

```bash
# Aumente limites de arquivo
sudo nano /etc/security/limits.conf

# Adicione:
* soft nofile 65536
* hard nofile 65536

# Ajuste kernel
sudo nano /etc/sysctl.conf

# Adicione:
net.core.somaxconn = 65536
net.ipv4.tcp_max_syn_backlog = 8192
```

---

**Dúvidas?** Consulte o README.md ou os comentários no código.
