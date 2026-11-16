-- Session middleware; see crescent/session.lua for options and storage.
--
--   app:use(require("crescent.middleware.session").create({ store = "cookie" }))
local Session = require("crescent.session")

return {
    create = Session.middleware,
}
