# 🚀 Guia de Instalação Rápida - Crescent Framework

Este guia irá ajudá-lo a instalar todas as dependências necessárias para executar o Crescent Framework.

## 📋 Dependências Necessárias

- **LuaRocks** - Gerenciador de pacotes Lua
- **Luvit** - Runtime assíncrono baseado em LuaJIT
- **MySQL** (opcional) - Banco de dados
- **luasql-mysql** (opcional) - Driver MySQL para Lua

## ⚡ Instalação Automática (Recomendado)

Execute o script de instalação que verifica e instala todas as dependências:

```bash
./install-dependencies.sh
```

### O que o script faz?

1. **Detecta seu sistema operacional** (macOS ou Linux)
2. **Verifica dependências instaladas**
3. **Instala o que está faltando:**
   - LuaRocks (se necessário)
   - Luvit (se necessário)
   - MySQL + luasql-mysql (se você optar)
   - Dependências Lua adicionais (opcional)

### Interativo e Seguro

O script pergunta antes de instalar cada componente:
- ✅ Você controla o que será instalado
- ✅ Pode pular MySQL se não precisar
- ✅ Mostra progresso e erros claramente

## 🔧 Instalação Manual

Se preferir instalar manualmente ou o script automático falhar:

### 1. Instalar LuaRocks

#### macOS
```bash
brew install luarocks
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install -y luarocks
```

#### Fedora/RHEL
```bash
sudo dnf install -y luarocks
```

### 2. Instalar Luvit

#### macOS
```bash
brew install luvit
```

#### Linux
```bash
# Instale dependências de compilação
sudo apt-get install -y git build-essential cmake

# Baixe e compile Luvit
curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh

# Mova para PATH
sudo mv lit luvit luvi /usr/local/bin/
```

### 3. Instalar MySQL (Opcional)

#### macOS
```bash
brew install mysql

# Iniciar MySQL
brew services start mysql
```

#### Ubuntu/Debian
```bash
sudo apt-get install -y mysql-server libmysqlclient-dev

# Iniciar MySQL
sudo systemctl start mysql
```

### 4. Instalar luasql-mysql (Opcional)

```bash
# Script automático
./install-mysql.sh

# Ou manualmente
luarocks install luasql-mysql

# Se falhar, tente com sudo
sudo luarocks install luasql-mysql
```

## ✅ Verificar Instalação

Após instalar as dependências, verifique se tudo está funcionando:

### Verificar LuaRocks
```bash
luarocks --version
# Esperado: LuaRocks X.X.X
```

### Verificar Luvit
```bash
luvit --version
# Esperado: luvit X.X.X
```

### Verificar luasql-mysql (se instalado)
```bash
luvit -e "require('luasql.mysql'); print('MySQL OK')"
# Esperado: MySQL OK
```

## 🎯 Próximos Passos

Após instalar todas as dependências:

### 1. Configure o Ambiente

```bash
# Copie o arquivo de exemplo
cp .env.example .env

# Edite com suas configurações
nano .env
```

Configure suas credenciais de banco de dados no `.env`:
```env
DB_HOST=localhost
DB_PORT=3306
DB_NAME=seu_banco
DB_USER=seu_usuario
DB_PASSWORD=sua_senha
```

### 2. Execute as Migrations (se usar banco de dados)

```bash
# Cria as tabelas no banco
luvit crescent-cli.lua migrate:run
```

### 3. Inicie o Servidor

```bash
luvit app.lua
```

Você verá:
```
✓ Módulo Hello carregado
🌙 Crescent server listening on http://0.0.0.0:8080
```

### 4. Teste a API

```bash
# Teste endpoint de health
curl http://localhost:8080/hello

# Crie um registro
curl -X POST http://localhost:8080/hello \
  -H "Content-Type: application/json" \
  -d '{"name":"Teste"}'
```

## 🐛 Solução de Problemas

### LuaRocks não encontrado após instalação

**macOS (Homebrew):**
```bash
# Adicione ao PATH
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**Linux:**
```bash
# Adicione ao PATH
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Luvit não encontrado no Linux

```bash
# Verifique se está no PATH
which luvit

# Se não estiver, adicione manualmente
sudo ln -s /caminho/para/luvit /usr/local/bin/luvit
```

### Erro ao instalar luasql-mysql

**macOS:**
```bash
# Instale MySQL primeiro
brew install mysql

# Tente novamente
luarocks install luasql-mysql
```

**Ubuntu/Debian:**
```bash
# Instale headers de desenvolvimento
sudo apt-get install libmysqlclient-dev

# Tente novamente
sudo luarocks install luasql-mysql
```

### Permissões negadas

Se encontrar erros de permissão ao instalar com LuaRocks:

```bash
# Tente com sudo
sudo luarocks install nome-do-pacote

# Ou configure LuaRocks para usar diretório local
mkdir -p ~/.luarocks
luarocks config rocks_trees --add ~/.luarocks
```

### MySQL não conecta

1. Verifique se o MySQL está rodando:
   ```bash
   # macOS
   brew services list
   
   # Linux
   sudo systemctl status mysql
   ```

2. Verifique suas credenciais no `.env`

3. Teste a conexão manualmente:
   ```bash
   mysql -u seu_usuario -p
   ```

## 📚 Recursos Adicionais

- **Documentação Completa:** [https://crescentframework.dev/docs.html](https://crescentframework.dev/docs.html)
- **GitHub Issues:** [https://github.com/daniel-m-tfs/crescent-framework/issues](https://github.com/daniel-m-tfs/crescent-framework/issues)
- **Luvit Docs:** [https://luvit.io/](https://luvit.io/)
- **LuaRocks:** [https://luarocks.org/](https://luarocks.org/)

## 💡 Dicas

1. **Use o script automático** - É a forma mais fácil e confiável
2. **Instale MySQL só se precisar** - Você pode começar sem banco de dados
3. **Mantenha dependências atualizadas:**
   ```bash
   luarocks update
   ```
4. **Use ambientes virtuais** para projetos diferentes

## 🎉 Pronto!

Agora você tem tudo instalado e está pronto para desenvolver com o Crescent Framework!

Se tiver problemas, abra uma issue no GitHub: 
[https://github.com/daniel-m-tfs/crescent-framework/issues](https://github.com/daniel-m-tfs/crescent-framework/issues)

---

**Happy Coding! 🌙**
