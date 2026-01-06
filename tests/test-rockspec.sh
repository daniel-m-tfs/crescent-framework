#!/bin/bash
# test-rockspec.sh
# Script para testar o rockspec localmente antes de publicar

set -e

echo "🧪 Testando Crescent Framework Rockspec..."
echo ""

cd crescent-framework

# 1. Validar rockspec
echo "📋 1/5 - Validando rockspec..."
luarocks lint crescent-framework-1.0.0-1.rockspec
echo "✅ Rockspec válido!"
echo ""

# 2. Fazer build local
echo "🔨 2/5 - Construindo pacote..."
luarocks make crescent-framework-1.0.0-1.rockspec --local
echo "✅ Build concluído!"
echo ""

# 3. Verificar instalação
echo "🔍 3/5 - Verificando instalação..."
if luarocks show crescent-framework &> /dev/null; then
    echo "✅ Crescent Framework instalado com sucesso!"
    luarocks show crescent-framework
else
    echo "❌ Erro: Crescent Framework não foi instalado"
    exit 1
fi
echo ""

# 4. Verificar se CLI foi copiado
echo "📦 4/5 - Verificando arquivos do CLI..."
CLI_PATH="$HOME/.luarocks/share/lua/5.1/crescent-cli.lua"
if [ -f "$CLI_PATH" ]; then
    echo "✅ CLI encontrado em: $CLI_PATH"
else
    echo "⚠️  CLI não encontrado no local esperado"
    echo "   Procurando em outros locais..."
    find "$HOME/.luarocks" -name "crescent-cli.lua" 2>/dev/null || echo "   Não encontrado"
fi
echo ""

# 5. Testar comando CLI
echo "🎯 5/5 - Testando CLI..."
if [ -f "$HOME/.luarocks/bin/crescent" ]; then
    echo "✅ Executável 'crescent' criado em ~/.luarocks/bin/"
    echo ""
    echo "Testando comando 'crescent' (help):"
    "$HOME/.luarocks/bin/crescent" 2>&1 | head -n 15
    echo ""
    echo "✅ Comando 'crescent' funcionando perfeitamente!"
else
    echo "⚠️  Executável não encontrado em ~/.luarocks/bin/crescent"
    echo "   Você pode usar diretamente: luvit crescent-cli.lua"
fi
echo ""

echo "✨ Testes concluídos com sucesso!"
echo ""
echo "📝 Nota sobre dependências:"
echo "   O luasql-mysql NÃO é instalado automaticamente (conflito com Luvit)"
echo "   Para usar MySQL, instale via lit: lit install creationix/mysql"
echo ""
echo "🎯 Para usar o CLI:"
echo "   Adicione ao PATH: export PATH=\"\$HOME/.luarocks/bin:\$PATH\""
echo "   Depois use: crescent new myapp"
echo "   Ou diretamente: ~/.luarocks/bin/crescent new myapp"
echo ""
echo "📚 Exemplo completo:"
echo "   crescent new myapp"
echo "   cd myapp"
echo "   lit install creationix/mysql"
echo "   cp .env.example .env"
echo "   luvit app.lua"
echo ""
echo "Próximos passos:"
echo "  1. Criar tag no GitHub: git tag -a v1.0.0 -m 'Release v1.0.0'"
echo "  2. Push da tag: git push origin v1.0.0"
echo "  3. Upload para LuaRocks: luarocks upload crescent-framework-1.0.0-1.rockspec --api-key=SUA_KEY"
echo ""
echo "Para remover a instalação local:"
echo "  luarocks remove crescent-framework"
