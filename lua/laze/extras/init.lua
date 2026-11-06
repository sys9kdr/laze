--- Opt-in maintenance helpers (lazy.nvim-style, without the UI).
---
--- The core never requires this module. It is split so consumers can load
--- only what they need:
---
---   require("laze.extras").setup()        -- register :Laze
---   require("laze.extras.commands")       -- command wiring only
---   require("laze.extras.maintenance")    -- update/clean/health/reload
---
--- The old singular `laze.extra` path still resolves here (see
--- lua/laze/extra.lua).

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
