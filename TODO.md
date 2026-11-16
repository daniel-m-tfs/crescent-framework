# TODO - Crescent

Roadmap para reconstruir o Crescent sobre Lua + OpenResty, inspirado no modelo do Lapis.

## Decisoes de arquitetura

- [x] Definir OpenResty/Nginx como runtime HTTP oficial.
- [x] Remover a dependencia conceitual de Luvit, LuaSocket e APIs HTTP proprias do framework.
- [x] Suportar primeiro a versao LuaJIT/Lua 5.1 fornecida pelo OpenResty; documentar compatibilidade antes de considerar Lua 5.4.
- [x] Usar APIs oficiais do OpenResty para request, response, timers, cosockets, TLS, buffering, limites e workers.
- [x] Manter o framework responsavel somente por: rotas, actions, configuracao, validacao, excecoes, modelos, queries, templates, testes e CLI.
- [ ] Definir uma API publica pequena e estavel antes de portar implementacoes antigas.
- [x] Usar o Crescent Framework atual como base de estilo e fonte de migracao, preservando nomes, organizacao e ergonomia onde nao houver acoplamento ao Luvit.

## Estrategia de reaproveitamento do Crescent atual

- [ ] Criar uma matriz de migracao com as colunas: modulo antigo, reutilizar, adaptar ou reescrever, dependencia de Luvit, testes existentes e destino no Crescent.
- [x] Reaproveitar a organizacao `src/<modulo>/{controllers,services,models,routes}` e manter o fluxo `Module.register(app)`.
- [x] Reaproveitar o estilo de controllers/actions: receber `ctx`, chamar service e retornar `ctx.json`, `ctx.text`, `ctx.view` ou `ctx.error`.
- [x] Reaproveitar o estilo de models declarativos: `table`, `fillable`, `guarded`, `hidden`, `timestamps`, `validates`, `relations` e hooks.
- [x] Reaproveitar a CLI e seus comandos `new`, `make:*`, `migrate`, `test` e `server`, trocando apenas o bootstrap e os comandos dependentes de Luvit.
- [ ] Reaproveitar templates, views, layouts, partials e convencoes de nomes, revisando o engine ETLua e o contexto de renderizacao para LuaJIT/OpenResty.
- [ ] Reaproveitar validadores, serializacao e helpers de teste depois de remover dependencias de `require`, `http`, `timer` e outros modulos do Luvit.
- [x] Reaproveitar o Query Builder somente depois de separar SQL, bindings e conexao em uma interface de adapter.
- [x] Reaproveitar migrations e o formato de arquivos, mas remover suposicoes de MySQL e declarar capacidades especificas por adapter.
- [x] Reaproveitar os testes de seguranca como regressao obrigatoria durante a migracao.
- [ ] Nao copiar `server.lua`, `request.lua`, `response.lua`, `bootstrap.lua`, `utils/http.lua` ou o connection manager antigo sem revisao: sao os pontos mais acoplados ao Luvit/MySQL.
- [ ] Nao transportar mocks que simulam sucesso, fallbacks silenciosos, limites especificos do runtime antigo ou contratos nao documentados.
- [ ] Portar primeiro um modulo vertical completo, da rota ao banco e template, antes de migrar todo o framework.

### Classificacao inicial dos componentes

- [ ] **Reutilizar com pouca alteracao:** estrutura de modules, controllers, services, models, routes, templates, validadores puros e helpers de teste.
- [ ] **Adaptar:** CLI, Query Builder, migrations, serializacao, configuracao, tratamento de erros e integracao com templates.
- [ ] **Reescrever:** runtime HTTP, bootstrap, request/response, cliente HTTP externo, pool de conexoes e integracao de filesystem.
- [ ] **Substituir por OpenResty/Nginx:** listener HTTP, TLS, keep-alive, body limits, timeouts, workers, static files, compressao e proxy.
- [ ] **Substituir por adapters LuaRocks:** drivers de banco, prepared statements, pool, migrations especificas e recursos de transacao.

## Responsabilidades do OpenResty/Nginx

- [ ] Receber conexoes HTTP e HTTPS.
- [ ] Terminar TLS e configurar certificados.
- [ ] Fazer keep-alive, buffering, limites de body/header, timeouts e controle de conexoes.
- [ ] Executar workers e distribuir requests.
- [ ] Fornecer cosockets para chamadas externas e banco quando apropriado.
- [ ] Servir arquivos estaticos quando isso for mais eficiente.
- [ ] Configurar proxy confiavel, IP real, compressao, cache e logs de acesso.
- [ ] Integrar health checks, graceful reload, systemd/container e observabilidade.

## Responsabilidades do Crescent

- [ ] Registrar e resolver rotas.
- [ ] Executar actions e compor middleware da aplicacao.
- [ ] Carregar e validar configuracao.
- [ ] Converter erros em respostas padronizadas.
- [ ] Validar entrada e dados de dominio.
- [ ] Definir modelos e relacoes.
- [ ] Construir queries por meio de adapters de banco.
- [ ] Renderizar templates com escaping seguro.
- [ ] Oferecer testes unitarios, integracao e helpers de teste.
- [ ] Fornecer CLI para projeto, codigo, migrations, testes e tarefas operacionais.

## Fase 0 - Contrato minimo

- [ ] Criar README com requisitos: OpenResty, LuaJIT, LuaRocks e banco suportado.
- [ ] Definir layout inicial do projeto.
- [ ] Definir convencoes de nomes para modules, actions, models, views e migrations.
- [ ] Definir formato de configuracao por ambiente sem segredos no repositorio.
- [ ] Definir politica de erros: codigo HTTP, identificador estavel, mensagem publica e detalhes apenas em desenvolvimento.
- [ ] Definir politica de compatibilidade Lua e proibir APIs exclusivas de Luvit.
- [x] Criar uma aplicacao exemplo minima com rota health e teste executavel.

## Fase 1 - Runtime da aplicacao

- [x] Criar o modulo de bootstrap da aplicacao sem iniciar servidor HTTP pelo framework.
- [x] Criar contexto de request baseado em `ngx`: metodo, URI, headers, query, body e estado.
- [x] Criar response API inicial: status, headers, texto e JSON.
- [x] Definir o ciclo de execucao de uma action dentro de `content_by_lua` ou entrypoint equivalente.
- [x] Tratar excecoes Lua com `xpcall` e error handler global.
- [x] Impedir vazamento de stack trace e dados sensiveis em producao.
- [ ] Definir comportamento para request abortada, timeout e erro de cosocket.
- [x] Criar request id e propaga-lo para logs e respostas.
- [x] Documentar o que pertence ao entrypoint OpenResty e o que pertence ao framework.

## Fase 2 - Router e actions

- [x] Implementar rotas por metodo HTTP e path.
- [ ] Implementar parametros obrigatorios e opcionais com sintaxe explicita, sem colisao silenciosa.
- [x] Decodificar parametros percent-encoded e rejeitar encoding invalido.
- [x] Implementar precedencia deterministica: literal, segmento parametrizado e wildcard.
- [x] Responder 404 quando o path nao existe.
- [x] Responder 405 com header `Allow` quando o path existe para outro metodo.
- [x] Implementar groups/prefixes e names de rota.
- [x] Implementar actions como funcoes ou objetos com dependencias explicitas.
- [x] Adicionar middleware de aplicacao somente quando houver necessidade real.
- [x] Testar rotas diretamente sem subir OpenResty.
- [x] Validar o primeiro endpoint com OpenResty real (`GET /health`).
- [x] Criar testes HTTP de integracao automatizados contra OpenResty.

## Fase 3 - Configuracao e ambiente

- [x] Criar loader de configuracao por ambiente.
- [x] Validar tipos, faixas e valores obrigatorios no boot.
- [x] Separar configuracao da aplicacao da configuracao Nginx/OpenResty.
- [x] Suportar `.env` somente como conveniencia local; em producao usar environment/secret manager.
- [ ] Redigir segredos em logs e mensagens de erro.
- [ ] Criar `config/example.lua` e `.env.example` sem credenciais reais.
- [ ] Criar teste de configuracao incompleta e configuracao invalida.

## Fase 4 - Validacao e erros

- [x] Criar API de validacao composavel: required, type, string, number, email, length, range, format e custom.
- [x] Definir mensagens e identificadores de erro estaveis.
- [x] Permitir validacao de params, query, headers e body.
- [x] Diferenciar erro de entrada `4xx`, erro de dominio e erro interno `5xx`.
- [x] Criar error handler configuravel por ambiente.
- [x] Garantir que validacao nunca execute query ou action parcialmente sem contrato explicito.
- [ ] Adicionar testes de Unicode, null bytes, limites e dados profundamente aninhados.

## Fase 5 - Banco, adapters e queries

- [x] Definir interface de adapter independente do banco: connect, query, execute, transaction e close.
- [x] Implementar o primeiro adapter com biblioteca LuaRocks mantida e documentar a escolha.
- [x] Decisao (2026-11): somente MySQL por enquanto (`lua-resty-mysql`); pgmoon removido.
- [ ] Rodar os testes de integracao MySQL com credenciais reais (usuario restrito ao banco de teste).
- [ ] Usar prepared statements nativos quando o adapter oferecer suporte.
- [ ] Manter bindings parametrizados como requisito de seguranca.
- [x] Definir pool/conexao por worker conforme as regras do OpenResty e do driver escolhido.
- [ ] Implementar timeout, retry limitado, rollback e liberacao de conexao.
- [x] Definir contrato de retorno de query, cursor, affected rows e erros.
- [x] Definir contrato inicial de retorno de query e erros para o Query Builder.
- [x] Implementar Query Builder com identificadores validados e valores parametrizados.
- [x] Implementar fundacao de modelos, fillable/guarded, timestamps e serializacao.
- [x] Implementar fundacao de soft delete.
- [x] Implementar persistencia inicial dos modelos via adapter.
- [x] Implementar verificacao de unicidade apoiada pelo adapter; constraints do schema continuam obrigatorias.
- [x] Implementar runner de migrations sem assumir que todo DDL e transacional.
- [x] Implementar relações lazy sem N+1 implícito.
- [x] Planejar eager loading.
- [ ] Adicionar EXPLAIN e testes de indices para queries importantes.
- [ ] Criar testes com SQLite quando possivel e testes de integracao com cada banco suportado.

## Fase 6 - Templates

- [x] Escolher engine de templates compativel com LuaJIT/OpenResty e com manutencao ativa.
- [x] Definir escaping HTML automatico para interpolacao comum.
- [x] Separar interpolacao escapada de HTML confiavel explicito.
- [x] Proibir templates fornecidos por usuarios ou criar sandbox real antes de aceitar esse caso.
- [x] Implementar layouts e partials sem acoplamento ao Luvit.
- [x] Implementar helpers de templates.
- [x] Integrar renderizacao de views ao Context e Response.
- [x] Adicionar cache de templates em producao e invalidacao em desenvolvimento.
- [ ] Adicionar testes contra XSS, includes invalidos e erros de compilacao.

## Fase 7 - CLI

- [x] Criar comando `new` para gerar uma aplicacao OpenResty funcional.
- [x] Criar `make:action`, `make:model`, `make:validator`, `make:route` e `make:migration`.
- [x] Criar `db:migrate`, `db:rollback` e `db:status`.
- [ ] Criar `db:seed`.
- [x] Validar nomes de projeto, modulo e arquivo antes de filesystem ou shell.
- [ ] Evitar shell injection e preferir APIs Lua/filesystem estruturadas.
- [x] Criar `test`.
- [ ] Criar `lint`, `check` e `routes`.
- [x] Gerar configuracao Nginx/OpenResty apenas como template revisavel, sem esconder responsabilidades de deploy.
- [x] Testar a CLI em diretorio temporario e com entradas maliciosas.

## Fase 8 - Testes

- [ ] Criar suite unitarias sem OpenResty real para router, config, validacao, erros, query builder e CLI.
- [x] Criar suite com ferramenta equivalente para requests reais no OpenResty.
- [ ] Testar GET, POST, JSON, form, multipart se suportado, headers, cookies e query string.
- [x] Testar GET, POST, JSON, form, headers e query string.
- [ ] Testar 404, 405, 400, 401, 403, 404 e 500.
- [ ] Testar timeout, request abortada, body acima do limite e banco indisponivel.
- [ ] Testar transactions, constraints, migrations e concorrencia no banco.
- [ ] Criar testes de seguranca para CRLF, XSS, SQL injection, path traversal, SSRF e secrets em logs.
- [ ] Criar testes de propriedade/fuzz para parser de URL, headers, JSON, validadores e bindings SQL.
- [ ] Fazer todos os testes rodarem em CI com versoes fixadas.

## Fase 9 - Observabilidade e performance

- [ ] Adicionar logs estruturados com request id e redacao de Authorization/cookies/secrets.
- [ ] Expor health check e readiness separados.
- [ ] Medir latencia, status, erros, queries lentas e pool por worker.
- [ ] Usar OpenResty/Nginx para limites, buffering, timeouts, cache e compressao.
- [ ] Criar benchmark de endpoint simples, JSON, body, template e banco.
- [ ] Criar teste de capacidade com conexoes crescentes e p50/p95/p99.
- [ ] Testar com e sem Nginx, com TLS e com multiplos workers.
- [ ] Definir criterio de degradacao antes de medir: erro, p99, throughput e consumo de memoria.
- [ ] Documentar que conexoes simultaneas nao equivalem automaticamente a usuarios humanos.

## Fase 10 - Producao

- [ ] Publicar uma release alpha interna com API congelada.
- [ ] Rodar migracoes em ambiente staging e validar rollback/restore.
- [ ] Criar configuracao OpenResty/Nginx de producao revisada manualmente.
- [ ] Configurar TLS, limits, proxy confiavel, logs, health checks e graceful reload.
- [ ] Executar com usuario de sistema sem privilegios.
- [ ] Configurar segredos por secret manager e rotacao.
- [ ] Configurar banco com privilegio minimo, TLS, backup e restore testado.
- [ ] Configurar deploy reproduzivel com rollback.
- [ ] Executar smoke test pos-deploy.
- [ ] Executar teste de carga controlado antes de abrir trafego.
- [ ] Definir alertas e runbooks para erro, latencia, memoria, banco e rollback.
- [ ] Fazer threat model e revisao de seguranca independentes.
- [ ] Publicar checklist de readiness e declarar explicitamente os bancos e versoes suportados.

## Criterios de pronto para producao

- [ ] API publica documentada e versionada.
- [ ] Nenhum teste critico depende de Luvit.
- [ ] CI verde em todas as versoes suportadas.
- [ ] Testes de integracao OpenResty e banco executados automaticamente.
- [ ] Nenhuma query usa interpolacao de valor sem binding.
- [ ] Erros internos nao vazam stack trace ou segredos.
- [ ] Timeouts, limites e cancelamentos definidos em OpenResty e na aplicacao.
- [ ] Backups e restore comprovados.
- [ ] Observabilidade e alertas ativos.
- [ ] Benchmark de capacidade repetido em ambiente representativo.
- [ ] Runbook de incidente e rollback testado.
- [ ] Release candidata aprovada por revisao tecnica e de seguranca.
