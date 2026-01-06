#!/bin/bash
# install-mysql.sh
# Script para instalar dependências MySQL no Crescent Framework

set -e

echo "🌙 Crescent Framework - Instalação MySQL"
echo ""

# Verifica se luarocks está instalado
if ! command -v luarocks &> /dev/null; then
    echo "❌ LuaRocks não encontrado!"
    echo ""
    echo "Instale primeiro:"
    echo "  macOS:   brew install luarocks"
    echo "  Ubuntu:  sudo apt-get install luarocks"
    echo "  Fedora:  sudo dnf install luarocks"
    exit 1
fi

echo "✓ LuaRocks encontrado: $(luarocks --version | head -n 1)"
echo ""

# Verifica MySQL dev libraries
echo "📦 Verificando bibliotecas MySQL..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if ! brew list mysql 2>/dev/null; then
        echo "⚠️  MySQL não encontrado, instalando..."
        brew install mysql
    fi
    echo "✓ MySQL instalado"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    if ! dpkg -l | grep -q libmysqlclient-dev; then
        echo "⚠️  libmysqlclient-dev não encontrado"
        echo "   Execute: sudo apt-get install libmysqlclient-dev"
        exit 1
    fi
    echo "✓ libmysqlclient-dev instalado"
fi

echo ""
echo "📥 Instalando luasql-mysql..."
if luarocks install luasql-mysql; then
    echo ""
    echo "✅ Instalação concluída com sucesso!"
    echo ""
    echo "🧪 Testando instalação..."
    
    # Testa se o módulo carrega
    luvit -e "local ok, luasql = pcall(require, 'luasql.mysql'); if ok then print('✓ luasql-mysql carregado com sucesso!') else print('❌ Erro ao carregar luasql-mysql') end"
    
    echo ""
    echo "🎉 Pronto! Agora você pode usar o MySQL no Crescent Framework"
    echo ""
    echo "📝 Próximos passos:"
    echo "   1. Configure o .env com suas credenciais MySQL:"
    echo "      DB_HOST=localhost"
    echo "      DB_PORT=3306"
    echo "      DB_NAME=seu_banco"
    echo "      DB_USER=seu_usuario"
    echo "      DB_PASSWORD=sua_senha"
    echo ""
    echo "   2. Teste a conexão:"
    echo "      luvit -e 'require(\"bootstrap\"); local MySQL = require(\"crescent.database.mysql\"); MySQL.test()'"
    echo ""
else
    echo ""
    echo "❌ Falha na instalação"
    echo ""
    echo "Problemas comuns:"
    echo "  1. MySQL não instalado - Execute: brew install mysql (macOS) ou apt-get install mysql-server (Linux)"
    echo "  2. Headers de desenvolvimento ausentes - Execute: apt-get install libmysqlclient-dev (Linux)"
    echo "  3. Permissões - Tente: sudo luarocks install luasql-mysql"
    exit 1
fi
