--- Opt-in maintenance entry point. The core never requires this module.
--- `laze.extra` is the public name; `lua/laze/extras/` holds the
--- implementation so consumers can load only part of it.

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
