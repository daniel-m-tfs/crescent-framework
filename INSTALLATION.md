# 🚀 Guia de Instalação - Crescent Framework

Este guia irá ajudá-lo a instalar o Crescent Framework usando apenas **Luvit** e **Lit**.

## 📋 Dependências Necessárias

- **Luvit** >= 2.18 - Runtime assíncrono baseado em LuaJIT
- **Lit** - Gerenciador de pacotes (vem com Luvit)
- **Git** - Para clonar projetos
- **MySQL** (opcional) - Banco de dados

## ⚡ Instalação Rápida

### 1. Instalar Luvit

#### macOS / Linux / WSL

```bash
# Método 1: Script oficial (recomendado)
curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh

# Método 2: Homebrew (macOS)
brew install luvit
```

Isso instalará:
- `luvit` - Runtime Lua assíncrono
- `lit` - Gerenciador de pacotes
- `luvi` - Runtime base

#### Verificar Instalação

```bash
luvit --version  # deve mostrar 2.18+
lit --version    # deve funcionar
```

### 2. Instalar Crescent Framework

```bash
# Instalar via Lit
lit install daniel-m-tfs/crescent-framework

# O comando 'crescent' agora está disponível
crescent --help
```

### 3. Instalar MySQL (Opcional)

Se você vai usar banco de dados:

```bash
# Instalar MySQL support via Lit
lit install creationix/mysql
```

## 🔧 Instalação Manual (Desenvolvimento)

Se você quer desenvolver o framework ou contribuir:

```bash
# Clonar repositório
git clone https://github.com/daniel-m-tfs/crescent-framework.git
cd crescent-framework

# Adicionar ao PATH (opcional)
export PATH="$PATH:$(pwd)/bin"

# Testar
luvit crescent-cli.lua --help
```

## � Criar Novo Projeto

```bash
# Criar novo projeto
crescent new meu-projeto

# Entrar no projeto
cd meu-projeto

# Configurar .env
cp .env.example .env
nano .env

# Iniciar servidor
crescent server
# ou
luvit app.lua
```

## 🗄️ Configurar MySQL (Opcional)

Se você vai usar o banco de dados:

### 1. Instalar MySQL

#### macOS
```bash
brew install mysql
brew services start mysql
```

#### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install mysql-server
sudo systemctl start mysql
```

### 2. Criar Banco de Dados

```bash
# Acessar MySQL
mysql -u root -p

# Criar banco e usuário
CREATE DATABASE crescent_db;
CREATE USER 'crescent'@'localhost' IDENTIFIED BY 'senha_segura';
GRANT ALL PRIVILEGES ON crescent_db.* TO 'crescent'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

### 3. Configurar .env

```bash
# Edite o arquivo .env no seu projeto
DB_HOST=localhost
DB_PORT=3306
DB_NAME=crescent_db
DB_USER=crescent
DB_PASSWORD=senha_segura
```

### 4. Instalar Driver MySQL

```bash
# Instalar via Lit
lit install creationix/mysql
```

## ✅ Verificar Instalação

```bash
# Verificar Luvit
luvit --version

# Verificar Lit
lit --version

# Verificar Crescent
crescent --help

# Testar criação de projeto
crescent new test-project
cd test-project
crescent server
```

Se tudo funcionar, você verá:
```
🌙 Iniciando Servidor Crescent

ℹ Iniciando aplicação...

🌙 Crescent Server
🚀 Servidor rodando em http://0.0.0.0:3000
📁 Ambiente: development
```

## 🐛 Troubleshooting

### "crescent: command not found"

O comando `crescent` não está no PATH. Soluções:

```bash
# Opção 1: Usar caminho completo do lit
~/.lit/bin/crescent --help

# Opção 2: Adicionar ao PATH
export PATH="$PATH:$HOME/.lit/bin"
echo 'export PATH="$PATH:$HOME/.lit/bin"' >> ~/.bashrc  # ou ~/.zshrc

# Opção 3: Usar via luvit diretamente
luvit crescent-cli.lua --help
```

### "module 'mysql' not found"

O driver MySQL não está instalado:

```bash
lit install creationix/mysql
```

### Erro de conexão com MySQL

Verifique:
1. MySQL está rodando: `brew services list` (macOS) ou `systemctl status mysql` (Linux)
2. Credenciais no `.env` estão corretas
3. Usuário tem permissões: veja seção "Criar Banco de Dados"

### Luvit não encontrado

```bash
# Reinstalar via script oficial
curl -L https://github.com/luvit/lit/raw/master/get-lit.sh | sh

# Ou via Homebrew (macOS)
brew install luvit
```

## 📚 Próximos Passos

- 📖 Leia o [README.md](README.md) para entender os conceitos
- 🗄️ Veja [DATABASE.md](DATABASE.md) para trabalhar com banco de dados
- 🔒 Confira [SECURITY.md](SECURITY.md) para boas práticas de segurança
- 🌐 Visite https://crescent.tyne.com.br para documentação completa

## 💡 Dicas

1. **Use o comando `crescent server`** ao invés de `luvit app.lua` para iniciar o servidor
2. **Crie módulos completos** com `crescent make:module User` para agilizar o desenvolvimento
3. **Use migrations** para controlar versões do banco de dados
4. **Consulte `crescent --help`** para ver todos os comandos disponíveis

## 🤝 Suporte

- Issues: https://github.com/daniel-m-tfs/crescent-framework/issues
- Discussões: https://github.com/daniel-m-tfs/crescent-framework/discussions
- Website: https://crescent.tyne.com.br

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
