#!/bin/bash
# sync-starter.sh
# Script para sincronizar framework e regenerar módulo users no crescent-starter

set -e  # Para em caso de erro

echo "🌙 Sincronizando Crescent Framework..."
echo ""

# Cores para output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Diretório base (crescent-framework)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Diretório raiz do projeto
PROJECT_ROOT="$(dirname "$BASE_DIR")"
STARTER_DIR="$PROJECT_ROOT/crescent-starter"

echo -e "${BLUE}📦 Sincronizando framework core...${NC}"
rsync -av --delete "$BASE_DIR/crescent/" "$STARTER_DIR/crescent/"
echo -e "${GREEN}✓ Framework sincronizado${NC}"
echo ""

echo -e "${BLUE}🛠️ Sincronizando CLI generator...${NC}"
cp "$BASE_DIR/crescent-cli.lua" "$STARTER_DIR/crescent-cli.lua"
chmod +x "$STARTER_DIR/crescent-cli.lua"
echo -e "${GREEN}✓ CLI sincronizado${NC}"
echo ""

echo -e "${BLUE}🔄 Sincronizando bootstrap...${NC}"
cp "$BASE_DIR/bootstrap.lua" "$STARTER_DIR/bootstrap.lua"
echo -e "${GREEN}✓ Bootstrap sincronizado${NC}"
echo ""

echo -e "${BLUE}⚙️ Sincronizando arquivos de configuração...${NC}"
mkdir -p "$STARTER_DIR/config"
cp "$BASE_DIR/config/development.lua" "$STARTER_DIR/config/"
cp "$BASE_DIR/config/production.lua" "$STARTER_DIR/config/"
echo -e "${GREEN}✓ Configs sincronizados${NC}"
echo ""

echo -e "${BLUE}🚀 Sincronizando arquivos de deployment...${NC}"
cp "$BASE_DIR/config/nginx.conf" "$STARTER_DIR/config/"
cp "$BASE_DIR/config/crescent.service" "$STARTER_DIR/config/"
echo -e "${GREEN}✓ Arquivos de deployment sincronizados${NC}"
echo ""

echo -e "${BLUE}📄 Copiando .env.example...${NC}"
cp "$BASE_DIR/.env.example" "$STARTER_DIR/.env.example"
echo -e "${GREEN}✓ .env.example copiado${NC}"
echo ""

echo -e "${BLUE}🔧 Copiando scripts de instalação...${NC}"
cp "$BASE_DIR/install-mysql.sh" "$STARTER_DIR/install-mysql.sh"
chmod +x "$STARTER_DIR/install-mysql.sh"
cp "$BASE_DIR/test-mysql.lua" "$STARTER_DIR/test-mysql.lua"
echo -e "${GREEN}✓ Scripts copiados${NC}"
echo ""

echo -e "${BLUE}🗑️ Removendo módulo users antigo...${NC}"
rm -rf "$STARTER_DIR/src/users"
echo -e "${GREEN}✓ Módulo users removido${NC}"
echo ""

echo -e "${BLUE}🎨 Regenerando módulo users...${NC}"
cd "$STARTER_DIR"
luvit crescent-cli.lua make:module Users
echo ""

echo -e "${GREEN}✅ Sincronização completa!${NC}"
echo ""
echo -e "${YELLOW}Arquivos sincronizados:${NC}"
echo "  - Framework core (crescent/)"
echo "  - CLI generator (crescent-cli.lua)"
echo "  - Bootstrap (bootstrap.lua)"
echo "  - Configurações (config/development.lua, config/production.lua)"
echo "  - Deployment (config/nginx.conf, config/crescent.service)"
echo "  - Ambiente (.env.example)"
echo "  - Documentação (README.md, DATABASE.md, MYSQL_IMPLEMENTATION.md)"
echo "  - Scripts (install-mysql.sh, test-mysql.lua)"
echo "  - Módulo users (src/users/)"
echo ""
echo -e "${YELLOW}Para testar:${NC}"
echo "  cd crescent-starter"
echo "  cp .env.example .env  # Ajuste as variáveis"
echo "  luvit app.lua"
echo ""
echo -e "${YELLOW}Para deploy em produção:${NC}"
echo "  1. Configure nginx.conf com seu domínio"
echo "  2. Configure crescent.service com seus caminhos"
echo "  3. Copie .env.example para .env e configure variáveis de produção"
