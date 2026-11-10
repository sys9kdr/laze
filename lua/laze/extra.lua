--- Opt-in maintenance entry point; the core never requires this. Surface: docs/extras.md.

local maintenance = require("laze.extras.maintenance")

local M = {
	update = maintenance.update,
	clean = maintenance.clean,
	health = maintenance.health,
	reload = maintenance.reload,
}

function M.setup()
	require("laze.extras.commands").setup(M)
end

return M
