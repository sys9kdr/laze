--- `:Laze` command wiring: requiring registers nothing, `setup(api)` registers. Surface: docs/extras.md.

local M = {}

local SUBCOMMANDS = { "update", "clean", "health", "reload" }

local function complete_subcommand(arglead, cmdline, _)
	local args = vim.split(cmdline, "%s+")
	if #args > 2 then
		return {}
	end
	return vim.tbl_filter(function(s)
		return s:sub(1, #arglead) == arglead
	end, SUBCOMMANDS)
end

---@param api { update: fun(), clean: fun(bang?: boolean), health: fun(), reload: fun() }
function M.setup(api)
	vim.api.nvim_create_user_command("Laze", function(cmd)
		local sub = cmd.fargs[1]
		local bang = cmd.bang
		-- Vim only recognizes a bang attached to the command name, so the documented and typed form
		-- (`:Laze clean!`) arrives as a trailing bang on the subcommand; map it back.
		if sub ~= nil and sub:sub(-1) == "!" then
			sub = sub:sub(1, -2)
			bang = true
		end
		if sub == "update" then
			api.update()
		elseif sub == "clean" then
			api.clean(bang)
		elseif sub == "health" then
			api.health()
		elseif sub == "reload" then
			api.reload()
		else
			vim.notify("laze: unknown subcommand (expected one of: update clean health reload)", vim.log.levels.WARN)
		end
	end, {
		nargs = "+",
		bang = true,
		complete = complete_subcommand,
		desc = "laze: maintenance (update/clean/health/reload)",
	})
end

return M
