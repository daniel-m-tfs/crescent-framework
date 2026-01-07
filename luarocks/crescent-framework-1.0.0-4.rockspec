package = "crescent-framework"
version = "1.0.0-4"

source = {
   url = "git://github.com/daniel-m-tfs/crescent-framework",
   tag = "v1.0.0-4"
}

description = {
   summary = "A modern, fast and elegant web framework for Luvit",
   detailed = [[
      Crescent Framework is a lightweight and powerful web framework built on top of Luvit.
      It provides an intuitive API, middleware support, robust routing, database ORM,
      and everything you need to build modern web applications with Lua.
   ]],
   homepage = "https://crescent.tyne.com.br",
   license = "MIT"
}

dependencies = {
   "lua >= 5.1"
   -- Note: For MySQL support, install via lit: lit install creationix/mysql
}

build = {
   type = "builtin",
   modules = {
      ["crescent.init"] = "crescent/init.lua",
      ["crescent.server"] = "crescent/server.lua",
      ["crescent.core.context"] = "crescent/core/context.lua",
      ["crescent.core.request"] = "crescent/core/request.lua",
      ["crescent.core.response"] = "crescent/core/response.lua",
      ["crescent.core.router"] = "crescent/core/router.lua",
      ["crescent.middleware.auth"] = "crescent/middleware/auth.lua",
      ["crescent.middleware.cors"] = "crescent/middleware/cors.lua",
      ["crescent.middleware.logger"] = "crescent/middleware/logger.lua",
      ["crescent.middleware.security"] = "crescent/middleware/security.lua",
      ["crescent.utils.headers"] = "crescent/utils/headers.lua",
      ["crescent.utils.path"] = "crescent/utils/path.lua",
      ["crescent.utils.string"] = "crescent/utils/string.lua",
      ["crescent.database.model"] = "crescent/database/model.lua",
      ["crescent.database.query_builder"] = "crescent/database/query_builder.lua",
      ["crescent.database.mysql"] = "crescent/database/mysql.lua",
      ["crescent.database.migrate"] = "crescent/database/migrate.lua",
      ["crescent-cli"] = "crescent-cli.lua",
   },
   install = {
      bin = {
         ["crescent"] = "bin/crescent"
      }
   },
   copy_directories = {
      "config",
      "examples"
   }
}
