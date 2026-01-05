#!/bin/bash

# deploy.sh - Script de deploy para produção
# Uso: ./deploy.sh

set -e

echo "🌙 Crescent Framework - Deploy Script"
echo "======================================"

# Variáveis
APP_DIR="/var/www/crescent"
USER="www-data"
GROUP="www-data"
SERVICE_NAME="crescent"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funções auxiliares
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verifica se está rodando como root
if [ "$EUID" -ne 0 ]; then 
    log_error "Por favor, execute como root (sudo)"
    exit 1
fi

# 1. Backup
log_info "Criando backup..."
if [ -d "$APP_DIR" ]; then
    BACKUP_DIR="/var/backups/crescent/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    cp -r "$APP_DIR" "$BACKUP_DIR/"
    log_info "Backup criado em: $BACKUP_DIR"
fi

# 2. Cria diretórios
log_info "Criando estrutura de diretórios..."
mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/logs"
mkdir -p "$APP_DIR/tmp"
mkdir -p "/etc/crescent"

# 3. Copia arquivos
log_info "Copiando arquivos da aplicação..."
cp -r crescent/ "$APP_DIR/"
cp example.lua "$APP_DIR/"
cp -r config/ "$APP_DIR/"

# 4. Configura permissões
log_info "Configurando permissões..."
chown -R $USER:$GROUP "$APP_DIR"
chmod -R 755 "$APP_DIR"
chmod -R 775 "$APP_DIR/logs"
chmod -R 775 "$APP_DIR/tmp"

# 5. Instala service do systemd
log_info "Instalando service do systemd..."
cp config/crescent.service /etc/systemd/system/
systemctl daemon-reload

# 6. Nginx
if command -v nginx &> /dev/null; then
    log_info "Configurando Nginx..."
    
    # Cria link simbólico para configuração
    cp config/nginx.conf /etc/nginx/sites-available/crescent
    
    if [ ! -L /etc/nginx/sites-enabled/crescent ]; then
        ln -s /etc/nginx/sites-available/crescent /etc/nginx/sites-enabled/crescent
    fi
    
    # Testa configuração
    nginx -t
    
    if [ $? -eq 0 ]; then
        log_info "Configuração do Nginx OK"
    else
        log_error "Erro na configuração do Nginx"
        exit 1
    fi
else
    log_warn "Nginx não encontrado. Instale manualmente."
fi

# 7. Variáveis de ambiente
log_info "Configurando variáveis de ambiente..."
if [ ! -f /etc/crescent/environment ]; then
    cat > /etc/crescent/environment << EOF
# Crescent Framework - Environment Variables
ENV=production

# Database (ajuste conforme necessário)
DB_HOST=localhost
DB_PORT=5432
DB_NAME=crescent_db
DB_USER=crescent_user
DB_PASSWORD=change_me

# Secrets (ALTERE ESTES VALORES)
JWT_SECRET=change_this_secret_key
API_KEY=change_this_api_key
EOF
    
    chmod 600 /etc/crescent/environment
    chown root:root /etc/crescent/environment
    
    log_warn "Arquivo de ambiente criado em /etc/crescent/environment"
    log_warn "IMPORTANTE: Edite este arquivo e altere os valores sensíveis!"
fi

# 8. Inicia/Reinicia serviços
log_info "Gerenciando serviços..."

# Para o serviço se estiver rodando
if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "Parando serviço existente..."
    systemctl stop $SERVICE_NAME
fi

# Inicia o serviço
log_info "Iniciando serviço Crescent..."
systemctl start $SERVICE_NAME
systemctl enable $SERVICE_NAME

# Aguarda um pouco
sleep 2

# Verifica status
if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "✓ Serviço Crescent iniciado com sucesso"
else
    log_error "✗ Falha ao iniciar serviço Crescent"
    log_info "Verificando logs:"
    journalctl -u $SERVICE_NAME -n 20 --no-pager
    exit 1
fi

# Reinicia Nginx se estiver rodando
if command -v nginx &> /dev/null && systemctl is-active --quiet nginx; then
    log_info "Reiniciando Nginx..."
    systemctl reload nginx
    log_info "✓ Nginx recarregado"
fi

# 9. Health check
log_info "Executando health check..."
sleep 3

if curl -f http://localhost:8080/health > /dev/null 2>&1; then
    log_info "✓ Health check passou"
else
    log_warn "Health check falhou. Verifique os logs:"
    log_info "  journalctl -u $SERVICE_NAME -f"
fi

# 10. Resumo
echo ""
echo "======================================"
log_info "Deploy concluído!"
echo ""
log_info "Comandos úteis:"
echo "  - Ver logs:        journalctl -u $SERVICE_NAME -f"
echo "  - Status:          systemctl status $SERVICE_NAME"
echo "  - Restart:         systemctl restart $SERVICE_NAME"
echo "  - Stop:            systemctl stop $SERVICE_NAME"
echo ""
log_warn "Próximos passos:"
echo "  1. Edite /etc/crescent/environment com valores reais"
echo "  2. Configure SSL no Nginx (/etc/nginx/sites-available/crescent)"
echo "  3. Ajuste domínio e certificados SSL"
echo "  4. Reinicie os serviços após ajustes"
echo ""
log_info "Aplicação disponível em: http://localhost:8080"
if command -v nginx &> /dev/null; then
    log_info "Nginx proxy disponível em: http://seu-dominio"
fi
echo "======================================"
