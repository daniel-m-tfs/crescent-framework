return {
  name = "daniel-m-tfs/crescent-framework",
  version = "1.0.2",
  description = "A modern, fast and elegant web framework for Luvit",
  tags = { "web", "framework", "http", "server", "orm", "mvc" },
  author = "Daniel M <contato@tyne.com.br>",
  homepage = "https://crescent.tyne.com.br",
  license = "MIT",
  
  dependencies = {
    "luvit/luvit@2.18.1",
  },

  -- Dependências OPCIONAIS via luarocks (não via lit/dependencies acima —
  -- ecossistema de pacotes diferente). Só necessárias se você usar os
  -- recursos correspondentes; sem elas, require() falha com uma mensagem
  -- de erro clara indicando o comando de instalação.
  --   luarocks install luasql-mysql   -- crescent.database.mysql (ORM/DB)
  --   luarocks install luasocket luasec -- crescent.utils.mail (SMTP)
  -- crescent.utils.http NÃO precisa de nenhuma dependência externa — usa
  -- os módulos http/https nativos e assíncronos do próprio Luvit.
  
  files = {
    "**.lua",
    "!tests/**",
    "!examples/**",
    "!luarocks/**",
  }
}
