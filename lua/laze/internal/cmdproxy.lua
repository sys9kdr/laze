--- Startup command bridge: a command typed before its plugin defined it. Required on first CmdUndefined hit during
--- startup, never at plan build (cold code; see docs/internal/performance.md).
---
--- During startup load_plugin uses `:packadd!`, which adds rtp but does not source plugin/ (Neovim's own startup phases
--- do, exactly once); a full `:packadd` would source plugin/ twice. So the retried command may still be undefined. This
--- proxy records the invocation and replays it at VimEnter, after the startup plugin phase, by which point the plugin's
--- `:command!` has usually replaced the proxy. Post-startup routes stay stateless.
local M = {}

local PROXY_DESC = "laze: defer command until VimEnter"

---@param calls table<string, string[]> per-plan replay queue
---@param cmd string
function M.defer(calls, cmd)
	if calls[cmd] then
		return
	end
	calls[cmd] = {}
	vim.api.nvim_create_user_command(cmd, function(command)
		local range = ""
		if command.range == 2 then
			range = ("%d,%d"):format(command.line1, command.line2)
		elseif command.range == 1 then
			range = tostring(command.line1)
		end
		local modifiers = command.mods ~= "" and (command.mods .. " ") or ""
		local args = command.args ~= "" and (" " .. command.args) or ""
		table.insert(calls[cmd], modifiers .. range .. cmd .. (command.bang and "!" or "") .. args)
	end, {
		nargs = "*",
		bang = true,
		range = true,
		bar = true,
		desc = PROXY_DESC,
	})
	vim.api.nvim_create_autocmd("VimEnter", {
		once = true,
		callback = function()
			local queued = calls[cmd]
			calls[cmd] = nil
			-- A plugin's `:command!` normally replaced this proxy already. If not (missing package, or a command the plugin
			-- never defines), remove it before replaying or the replay re-queues itself forever and masks the real "not an
			-- editor command" error.
			local current = vim.api.nvim_get_commands({ builtin = false })[cmd]
			-- `nvim_get_commands` exposes a user command's `desc` as `definition`.
			if current and current.definition == PROXY_DESC then
				pcall(vim.api.nvim_del_user_command, cmd)
			end
			for _, call in ipairs(queued or {}) do
				-- LuaLS sees `vim.cmd` as a callable table, not a function.
				---@diagnostic disable-next-line: param-type-mismatch
				pcall(vim.cmd, call)
			end
		end,
	})
end

return M
