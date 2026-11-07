--- Opt-in maintenance entry point (lazy.nvim-style, without the UI).
---
--- The core never requires this module. The implementation lives in
--- lua/laze/extras/ so consumers can load only what they need:
---
---   require("laze.extra").setup()          -- register :Laze
---   require("laze.extras.commands")        -- command wiring only
---   require("laze.extras.maintenance")     -- update/clean/health/reload
---
--- `laze.extra` is the public name; `extras/` is the implementation detail.

local maintenance = require("laze.extras.maintenance")

local M = {
	update = maintenance.update,
	clean = maintenance.clean,
	health = maintenance.health,
	reload = maintenance.reload,
}

--- Register the `:Laze` user command (update/clean/health/reload).
function M.setup()
	require("laze.extras.commands").setup(M)
end

return M
