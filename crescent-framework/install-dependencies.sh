#!/bin/bash
# install-dependencies.sh
# Script para instalar todas as dependências do Crescent Framework

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
echo ""
echo -e "${PURPLE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║                                                    ║${NC}"
echo -e "${PURPLE}║         ${CYAN}🌙  Crescent Framework${PURPLE}                  ║${NC}"
echo -e "${PURPLE}║         ${NC}Instalador de Dependências${PURPLE}              ║${NC}"
echo -e "${PURPLE}║                                                    ║${NC}"
echo -e "${PURPLE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Detecta sistema operacional
OS="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    echo -e "${BLUE}📟 Sistema detectado: macOS${NC}"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    echo -e "${BLUE}📟 Sistema detectado: Linux${NC}"
else
    echo -e "${RED}❌ Sistema operacional não suportado: $OSTYPE${NC}"
    echo "   Suportados: macOS, Linux"
    exit 1
fi
echo ""

# Função para verificar se um comando existe
command_exists() {
    command -v "$1" &> /dev/null
}

# Função para instalar Homebrew no macOS
install_homebrew() {
    echo -e "${YELLOW}📦 Homebrew não encontrado. Instalando...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Adiciona ao PATH se necessário
    if [[ "$OS" == "macos" ]]; then
        if [[ $(uname -m) == "arm64" ]]; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
    
    echo -e "${GREEN}✓ Homebrew instalado${NC}"
    echo ""
}

# Função para instalar LuaRocks
install_luarocks() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📦 Instalando LuaRocks...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [[ "$OS" == "macos" ]]; then
        if ! command_exists brew; then
            install_homebrew
        fi
        
        echo "   Executando: brew install luarocks"
        brew install luarocks
        
    elif [[ "$OS" == "linux" ]]; then
        if command_exists apt-get; then
            echo "   Executando: sudo apt-get update && sudo apt-get install -y luarocks"
            sudo apt-get update
            sudo apt-get install -y luarocks
        elif command_exists dnf; then
            echo "   Executando: sudo dnf install -y luarocks"
            sudo dnf install -y luarocks
        elif command_exists yum; then
            echo "   Executando: sudo yum install -y luarocks"
            sudo yum install -y luarocks
        else
            echo -e "${RED}❌ Gerenciador de pacotes não suportado${NC}"
            echo "   Instale LuaRocks manualmente: https://luarocks.org/"
            exit 1
        fi
    fi
    
    echo ""
    echo -e "${GREEN}✅ LuaRocks instalado: $(luarocks --version | head -n 1)${NC}"
    echo ""
}

# Função para instalar Luvit
install_luvit() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}🚀 Instalando Luvit...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [[ "$OS" == "macos" ]]; then
        if ! command_exists brew; then
            install_homebrew
        fi
        
        echo "   Executando: brew install luvit"
        brew install luvit
        
    elif [[ "$OS" == "linux" ]]; then
        # No Linux, precisamos compilar do source
        echo "   Baixando Luvit..."
        
        # Instala dependências de compilação
        if command_exists apt-get; then
            sudo apt-get install -y git build-essential cmake
        elif command_exists dnf; then
            sudo dnf install -y git gcc make cmake
        fi
        
        # Cria diretório temporário
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        
        # Clona e compila Luvit
        echo "   Compilando Luvit..."
        curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh
        
        # Move binários para /usr/local/bin
        sudo mv lit luvit luvi /usr/local/bin/
        
        # Limpa
        cd -
        rm -rf "$TEMP_DIR"
    fi
    
    echo ""
    echo -e "${GREEN}✅ Luvit instalado: $(luvit --version 2>&1 | head -n 1)${NC}"
    echo ""
}

# Função para instalar MySQL
install_mysql() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}🗄️  Instalando MySQL e dependências...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [[ "$OS" == "macos" ]]; then
        if ! brew list mysql &> /dev/null; then
            echo "   Executando: brew install mysql"
            brew install mysql
            echo ""
            echo -e "${YELLOW}💡 Para iniciar o MySQL:${NC}"
            echo "   brew services start mysql"
        else
            echo -e "${GREEN}✓ MySQL já está instalado${NC}"
        fi
        
    elif [[ "$OS" == "linux" ]]; then
        if command_exists apt-get; then
            echo "   Instalando MySQL Server e dev libraries..."
            sudo apt-get install -y mysql-server libmysqlclient-dev
            echo ""
            echo -e "${YELLOW}💡 Para iniciar o MySQL:${NC}"
            echo "   sudo systemctl start mysql"
        elif command_exists dnf; then
            sudo dnf install -y mysql-server mysql-devel
            echo ""
            echo -e "${YELLOW}💡 Para iniciar o MySQL:${NC}"
            echo "   sudo systemctl start mysqld"
        fi
    fi
    
    echo ""
}

# Função para instalar luasql-mysql
install_luasql_mysql() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}💎 Instalando luasql-mysql...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Verifica se MySQL está instalado
    if [[ "$OS" == "macos" ]]; then
        if ! brew list mysql &> /dev/null; then
            install_mysql
        fi
    fi
    
    echo "   Executando: luarocks install luasql-mysql"
    
    if luarocks install luasql-mysql; then
        echo ""
        echo -e "${GREEN}✅ luasql-mysql instalado com sucesso${NC}"
        
        # Testa a instalação
        echo ""
        echo "🧪 Testando instalação..."
        if luvit -e "local ok, luasql = pcall(require, 'luasql.mysql'); if ok then print('✓ luasql-mysql carregado com sucesso!') else print('❌ Erro ao carregar') os.exit(1) end"; then
            echo -e "${GREEN}✓ Teste passou!${NC}"
        else
            echo -e "${YELLOW}⚠️  Aviso: Módulo instalado mas teste falhou${NC}"
        fi
    else
        echo ""
        echo -e "${RED}❌ Falha ao instalar luasql-mysql${NC}"
        echo ""
        echo -e "${YELLOW}Tentando com sudo...${NC}"
        if sudo luarocks install luasql-mysql; then
            echo -e "${GREEN}✅ Instalado com sudo${NC}"
        else
            echo -e "${RED}❌ Falha na instalação${NC}"
            echo ""
            echo "   Problemas comuns:"
            echo "   1. MySQL não instalado"
            echo "   2. Headers de desenvolvimento ausentes"
            echo ""
            echo "   Execute o script install-mysql.sh separadamente"
            return 1
        fi
    fi
    
    echo ""
}

# Função para instalar dependências Lua adicionais
install_lua_dependencies() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📚 Instalando dependências Lua adicionais...${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Lista de dependências úteis
    local deps=("lua-cjson" "luafilesystem" "penlight")
    
    for dep in "${deps[@]}"; do
        if luarocks show "$dep" &> /dev/null; then
            echo -e "${GREEN}✓ $dep já está instalado${NC}"
        else
            echo "   Instalando $dep..."
            if luarocks install "$dep" &> /dev/null; then
                echo -e "${GREEN}✓ $dep instalado${NC}"
            else
                echo -e "${YELLOW}⚠️  Falha ao instalar $dep (opcional)${NC}"
            fi
        fi
    done
    
    echo ""
}

# ═══════════════════════════════════════════════════════════════
# INÍCIO DA INSTALAÇÃO
# ═══════════════════════════════════════════════════════════════

echo -e "${BLUE}🔍 Verificando dependências...${NC}"
echo ""

# 1. Verifica e instala LuaRocks
if command_exists luarocks; then
    echo -e "${GREEN}✓ LuaRocks encontrado: $(luarocks --version | head -n 1)${NC}"
else
    echo -e "${YELLOW}⚠️  LuaRocks não encontrado${NC}"
    read -p "   Deseja instalar LuaRocks? (s/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[SsYy]$ ]]; then
        install_luarocks
    else
        echo -e "${RED}❌ LuaRocks é obrigatório. Abortando.${NC}"
        exit 1
    fi
fi

# 2. Verifica e instala Luvit
if command_exists luvit; then
    echo -e "${GREEN}✓ Luvit encontrado: $(luvit --version 2>&1 | head -n 1)${NC}"
else
    echo -e "${YELLOW}⚠️  Luvit não encontrado${NC}"
    read -p "   Deseja instalar Luvit? (s/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[SsYy]$ ]]; then
        install_luvit
    else
        echo -e "${RED}❌ Luvit é obrigatório. Abortando.${NC}"
        exit 1
    fi
fi

echo ""

# 3. Pergunta sobre MySQL
echo -e "${BLUE}🗄️  Configuração de Banco de Dados${NC}"
echo ""
read -p "   Deseja instalar MySQL e luasql-mysql? (s/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[SsYy]$ ]]; then
    install_mysql
    install_luasql_mysql
else
    echo -e "${YELLOW}⚠️  Pulando instalação do MySQL${NC}"
    echo "   Você pode instalar depois com: ./install-mysql.sh"
    echo ""
fi

# 4. Dependências Lua adicionais
echo -e "${BLUE}📦 Dependências opcionais${NC}"
echo ""
read -p "   Deseja instalar dependências Lua adicionais? (s/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[SsYy]$ ]]; then
    install_lua_dependencies
else
    echo -e "${YELLOW}⚠️  Pulando dependências opcionais${NC}"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════
# RESUMO FINAL
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                    ║${NC}"
echo -e "${GREEN}║         🎉  INSTALAÇÃO CONCLUÍDA!                 ║${NC}"
echo -e "${GREEN}║                                                    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${CYAN}📋 Dependências instaladas:${NC}"
echo ""

if command_exists luarocks; then
    echo -e "   ${GREEN}✓${NC} LuaRocks: $(luarocks --version | head -n 1)"
fi

if command_exists luvit; then
    echo -e "   ${GREEN}✓${NC} Luvit: $(luvit --version 2>&1 | head -n 1)"
fi

if luvit -e "require('luasql.mysql')" &> /dev/null; then
    echo -e "   ${GREEN}✓${NC} luasql-mysql: instalado"
fi

echo ""
echo -e "${YELLOW}📝 Próximos passos:${NC}"
echo ""
echo "   1. Configure o arquivo .env:"
echo "      cp .env.example .env"
echo ""
echo "   2. Edite suas credenciais de banco de dados no .env"
echo ""
echo "   3. Execute as migrations:"
echo "      luvit crescent-cli.lua migrate:run"
echo ""
echo "   4. Inicie o servidor:"
echo "      luvit main.lua"
echo ""
echo -e "${CYAN}📚 Documentação:${NC} https://crescentframework.dev"
echo -e "${CYAN}🐛 Issues:${NC} https://github.com/daniel-m-tfs/crescent-framework/issues"
echo ""
echo -e "${PURPLE}Happy coding! 🌙${NC}"
echo ""
