# 🌙 Crescent Framework

Framework web modular para Luvit - Inspirado em NestJS e Laravel.

## 📦 Conteúdo

Este repositório contém:

- **`crescent/`** - Framework core (produção)
- **`crescent-starter/`** - Pacote inicial pronto para distribuição ⭐
- **`src/`** - Módulos de exemplo
- **`config/`** - Configurações

## 🚀 Quick Start

### Opção 1: Usar o Starter Kit (Recomendado)

```bash
cd crescent-starter
luvit app.lua
```

Veja `crescent-starter/README.md` para documentação completa.

### Opção 2: Usar o projeto de desenvolvimento

```bash
luvit app.lua
```

## 🎯 Para Distribuir

Use a pasta `crescent-starter/` - ela contém:

- ✅ Framework completo
- ✅ Exemplo CRUD funcionando
- ✅ CLI generator
- ✅ Bootstrap configurado
- ✅ Zero configuração necessária
- ✅ Documentação completa

## 🏗️ Estrutura

```
Crescent Framework/
├── crescent/              # Framework core
│   ├── init.lua
│   ├── server.lua
│   ├── core/             # Router, Context, Request, Response
│   ├── middleware/       # CORS, Logger, Security, Auth
│   ├── database/         # Query Builder
│   └── utils/            # Utilitários
│
├── crescent-starter/     # ⭐ PACOTE PARA DISTRIBUIÇÃO
│   ├── app.lua
│   ├── crescent/         # Cópia do framework
│   ├── src/hello/        # Exemplo CRUD
│   └── crescent-cli.lua  # CLI generator
│
├── src/                  # Módulos de exemplo (dev)
├── config/               # Configurações (dev)
├── app.lua               # App de desenvolvimento
└── bootstrap.lua         # Bootstrap
```

## 🎨 Features

- ✅ Arquitetura modular (Controllers → Services → Models)
- ✅ CLI generator (Artisan-style)
- ✅ Middleware stack (CORS, Logger, Security, Auth)
- ✅ Roteamento com parâmetros
- ✅ Query Builder (Laravel-inspired)
- ✅ Context API simples
- ✅ Zero configuração

## 🛠️ Desenvolvimento

```bash
# Gerar novo módulo
luvit crescent-cli.lua make:module User

# Iniciar servidor
luvit app.lua

# Parar servidor
pkill -f "luvit app"

# Sincronizar mudanças para crescent-starter
./sync-starter.sh
```

### Script de Sincronização

O script `sync-starter.sh` automatiza:
1. Sincroniza framework core (`crescent/`)
2. Sincroniza CLI generator
3. Sincroniza bootstrap
4. Regenera módulo hello com templates atualizados

**Use sempre que fizer mudanças no framework ou CLI!**

## 📚 Documentação

Veja `crescent-starter/README.md` para:
- Quick start
- Criar módulos
- Exemplos de código
- Comandos CLI
- Configuração

## 📦 Requisitos

- [Luvit](https://luvit.io/) v2.18+

## 📄 Licença

MIT License

---

**🌙 Crescent Framework** - Modular web framework for Luvit
