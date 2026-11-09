--- Startup command proxy: bridge a command fired before its plugin has
--- defined it. Required on first CmdUndefined hit during startup, never at
--- plan build (the body is cold code, see docs/performance.md).
---
--- A CmdUndefined handler normally loads a plugin and lets Neovim retry the
--- command immediately. That is sufficient after VimEnter: `:packadd` sources
--- plugin/ synchronously, and the plugin's `:command!` definition exists
--- before Neovim retries the original command.
---
--- Startup is deliberately different. load_plugin uses `:packadd!` while
--- vim_did_enter == 0. `:packadd!` adds the plugin directory to rtp but does
--- not source plugin/; Neovim's later startup plugin/ and after/plugin/
--- phases do that exactly once. Using full `:packadd` here would make a
--- command available immediately, but would also source plugin/ twice when
--- those startup phases arrive. The activation invariant therefore wins.
---
--- The otherwise unavoidable gap is: CmdUndefined fires, laze activates the
--- package with `:packadd!`, Neovim retries the command, but the plugin has
--- not yet defined it. Install a short-lived user-command proxy before that
--- retry. It records the fully retried invocation; VimEnter runs after the
--- startup plugin phase, by which time a normal plugin `:command!` has
--- replaced the proxy. We then replay the original range/bang/modifiers/
--- arguments against the plugin command. This is only a startup bridge:
--- post-startup command routes remain stateless CmdUndefined handlers.
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
			-- A plugin's `:command!` normally replaces this proxy during the
			-- startup plugin phase. If it did not (missing package, or a
			-- plugin which does not define the advertised command), remove our
			-- proxy before replaying. Otherwise the replay would re-queue
			-- itself forever and mask the real "not an editor command" error.
			local current = vim.api.nvim_get_commands({ builtin = false })[cmd]
			if current and current.desc == PROXY_DESC then
				pcall(vim.api.nvim_del_user_command, cmd)
			end
			for _, call in ipairs(queued or {}) do
				pcall(vim.cmd, call)
			end
		end,
	})
end

return M
