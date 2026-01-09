return {
  name = "daniel-m-tfs/crescent-framework",
  version = "1.0.1",
  description = "A modern, fast and elegant web framework for Luvit",
  tags = { "web", "framework", "http", "server", "orm", "mvc" },
  author = "Daniel M <daniel@tyne.com.br>",
  homepage = "https://crescent.tyne.com.br",
  license = "MIT",
  
  dependencies = {
    "luvit/luvit@2.18.1",
  },
  
  files = {
    "**.lua",
    "!tests/**",
    "!examples/**",
    "!luarocks/**",
  }
}
