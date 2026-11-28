--- Trigger-time behavior, required at the first fire rather than at plan build: none of this runs on a startup that
--- never hits a trigger (docs/internal/performance.md). Everything these bodies need is an explicit argument, so the plan's
--- loader state stays in its closure.
local M = {}

---@param mode string
---@param lhs string
---@param buf? integer
local function del_map(mode, lhs, buf)
	if buf then
		pcall(vim.keymap.del, mode, lhs, { buffer = buf })
	else
		pcall(vim.keymap.del, mode, lhs)
	end
end

-- Re-fire the triggering event after a load so autocmds the plugin registers while loading see it (an ft plugin's
-- FileType handler would otherwise miss the buffer). No re-entry guard: a nested load replays its own chain too,
-- matching lazy.nvim (a handler that keeps triggering loads can recurse there as well).
---@param event string
---@param exec_opts table
function M.refire(event, exec_opts)
	exec_opts.modeline = false
	pcall(vim.api.nvim_exec_autocmds, event, exec_opts)
end

-- Event dependencies: loading on FileType also replays BufReadPost/BufReadPre, and BufReadPost replays BufReadPre
-- (lazy.nvim/core/handler/event.lua M.triggers). A plugin loaded by FileType may register BufReadPost handlers that
-- must still see the current buffer, even though the real BufReadPost already passed.
local TRIGGERS = {
	FileType = "BufReadPost",
	BufReadPost = "BufReadPre",
}

-- Groups that already handle `event`, captured before the load. lazy.nvim excludes them from the replay so a
-- pre-existing handler does not see the event twice. FileType is exempt: its replay exists to hand the current buffer
-- to freshly loaded ft handlers.
---@param event string
---@return table<string, boolean>
local function snapshot_groups(event)
	local groups = {}
	if event == "FileType" then
		return groups
	end
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = event })) do
		if autocmd.group_name then
			groups[autocmd.group_name] = true
		end
	end
	return groups
end

-- Replay for what the load added, one exec per augroup. Ungrouped autocmds are skipped: they cannot be told apart
-- from pre-existing ones (lazy.nvim does the same).
---@param event string
---@param ev table
---@param exclude table<string, boolean>
local function replay_groups(event, ev, exclude)
	local done = {}
	local is_user = event == "User"
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = event })) do
		local name = autocmd.group_name
		if name and not exclude[name] and not done[name] then
			done[name] = true
			if is_user then
				M.refire(event, { group = name, pattern = ev.match, data = ev.data })
			else
				M.refire(event, { group = name, buffer = ev.buf, data = ev.data })
			end
		end
	end
end

-- Replay state for `event` and its dependencies, captured before the load: root first (BufReadPre), then the
-- triggering event. Only the triggering event gets the event data: lazy.nvim's get_state clears `data` while walking
-- dependencies, which are prepended to its list, so the data ends up on the event that actually fired.
---@param event string
---@param ev table
---@return table[]
local function snapshot_chain(event, ev)
	local chain = {}
	local cursor = event
	while cursor do
		table.insert(chain, 1, cursor)
		cursor = TRIGGERS[cursor]
	end
	local state = {}
	for i, name in ipairs(chain) do
		state[i] = {
			event = name,
			exclude = name ~= "FileType" and snapshot_groups(name) or nil,
			buf = ev.buf,
			match = ev.match,
			data = name == event and ev.data or nil,
		}
	end
	return state
end

---@param state table[]
local function replay_state(state)
	for _, s in ipairs(state) do
		if s.event == "FileType" then
			M.refire("FileType", { buffer = s.buf, data = s.data })
		elseif s.event == "User" then
			M.refire("User", { pattern = s.match, data = s.data })
		else
			replay_groups(s.event, s, s.exclude)
		end
	end
end

--- One bucket of `(event, pattern)` variants; only this event's routes load.
---@param ev table
---@param bucket_routes { event: string, ids: string[] }[]
---@param load fun(id: string): boolean
function M.event(ev, bucket_routes, load)
	local state = snapshot_chain(ev.event, ev)
	local loaded_any = false
	for _, route in ipairs(bucket_routes) do
		if route.event == ev.event then
			for _, id in ipairs(route.ids) do
				if load(id) then
					loaded_any = true
				end
			end
		end
	end
	-- Re-fire only if this dispatch loaded something; the buffer is forwarded so buffer-local handlers see the
	-- original ev.buf. FileType replays globally (lazy.nvim exempts it from augroup exclusion); the rest replay
	-- per fresh augroup so pre-existing handlers stay single-fire.
	if loaded_any then
		replay_state(state)
	end
end

---@param ev table
---@param ids string[]
---@param load fun(id: string): boolean
function M.ft(ev, ids, load)
	local state = snapshot_chain("FileType", ev)
	local loaded_any = false
	for _, id in ipairs(ids) do
		if load(id) then
			loaded_any = true
		end
	end
	-- Re-fire only if something loaded: its handlers missed the natural pass. Otherwise every matching handler
	-- already saw this FileType.
	if loaded_any then
		replay_state(state)
	end
end

---@param ev table
---@param ids string[]
---@param startup_cmd_calls table<string, string[]>
---@param load fun(id: string): boolean
function M.cmd(ev, ids, startup_cmd_calls, load)
	for _, id in ipairs(ids) do
		load(id)
	end
	if vim.v.vim_did_enter == 0 then
		-- Cold: the proxy body is parsed only when a startup command actually misfires.
		require("laze.internal.cmdproxy").defer(startup_cmd_calls, ev.match)
	end
end

local STUB_DESC = "laze: lazy command trigger"

--- Rebuild the command line a stub invocation replays after the load. Raw `args` (not `fargs`) keeps quoting and `|`
--- verbatim, so the plugin's own command parses exactly what was typed.
---@param cmd string
---@param command table `nvim_create_user_command` callback arg
---@return string
local function replay_line(cmd, command)
	local range = ""
	if command.range == 2 then
		range = ("%d,%d"):format(command.line1, command.line2)
	elseif command.range == 1 then
		range = tostring(command.line1)
	end
	local modifiers = command.mods ~= "" and (command.mods .. " ") or ""
	local args = command.args ~= "" and (" " .. command.args) or ""
	return modifiers .. range .. cmd .. (command.bang and "!" or "") .. args
end

--- Install user command stubs for Tab completion and command dispatch: the names complete, and argument completion
--- loads the plugin and defers to its own `complete` (Neovim never fires `CmdUndefined` while completing).
--- Called on the first CmdlineEnter, so a session that never opens the cmdline registers nothing.
---@param cmds table<string, string[]>
---@param startup_cmd_calls table<string, string[]>
---@param load fun(id: string): boolean
function M.install_cmd_stubs(cmds, startup_cmd_calls, load)
	local existing_cmds = vim.api.nvim_get_commands({ builtin = false })
	for cmd, ids in pairs(cmds) do
		if not existing_cmds[cmd] then
			-- A name Neovim will not accept (lowercase, `-`, `_`) can never be a command either; one bad spec must not
			-- break every other stub, so register them one by one.
			local ok, err = pcall(vim.api.nvim_create_user_command, cmd, function(command)
				-- Delete first: after the load this would remove the plugin's own command instead of the stub.
				pcall(vim.api.nvim_del_user_command, cmd)
				for _, id in ipairs(ids) do
					load(id)
				end
				local line = replay_line(cmd, command)
				if vim.v.vim_did_enter == 0 then
					-- A cmdline opened during startup (e.g. `nvim +"normal! :"`): plugin/ is not sourced yet, so replay
					-- through the bridge the CmdUndefined route uses (docs/internal/startup-lazy-activation.md).
					require("laze.internal.cmdproxy").defer(startup_cmd_calls, cmd)
					vim.cmd(line)
					return
				end
				if vim.fn.exists(":" .. cmd) == 0 then
					require("laze.internal.diag").warn(("command '%s' is not defined by the plugin(s) it loads"):format(cmd))
					return
				end
				vim.cmd(line)
			end, {
				nargs = "*",
				bang = true,
				range = true,
				desc = STUB_DESC,
				complete = function(_, line)
					pcall(vim.api.nvim_del_user_command, cmd)
					for _, id in ipairs(ids) do
						load(id)
					end
					return vim.fn.getcompletion(line, "cmdline")
				end,
			})
			if not ok then
				require("laze.internal.diag").warn(("command '%s' was not registered: %s"):format(cmd, tostring(err)))
			end
		end
	end
end

--- Clear all remaining command stubs on rebuild.
function M.clear_cmd_stubs()
	local command_desc = require("laze.internal.cmdproxy").command_desc
	local commands = vim.api.nvim_get_commands({ builtin = false })
	for name, def in pairs(commands) do
		if command_desc(def) == STUB_DESC then
			pcall(vim.api.nvim_del_user_command, name)
		end
	end
end

---@param load fun(id: string): boolean
---@param mode string
---@param lhs string
---@param ids string[]
---@param rhs string|fun()|nil
---@param buf? integer
function M.keys(load, mode, lhs, ids, rhs, buf)
	if rhs == nil then
		-- Delete the trigger before loading: after the load it would also delete the plugin's fresh map
		-- (vim.keymap.del removes every map for this lhs in the mode). Other mode variants are separate maps
		-- and stay.
		del_map(mode, lhs, buf)
	end
	for _, id in ipairs(ids) do
		load(id)
	end
	if rhs == nil then
		-- Replay the key so the plugin's own map handles it. Queue it BEFORE keys already behind the trigger
		-- ('i'): with append, `gcA` would run `A` first and then insert `gc` literally instead of firing `gcA`.
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "i", true)
	elseif type(rhs) == "function" then
		rhs()
	else
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(rhs, true, false, true), "i", true)
	end
end

-- Keymaps have no group to clear. Only maps still carrying the trigger desc go: a plugin map that took over the lhs,
-- or a user map sharing it, must survive a rebuild.
---@param installed { mode: string, lhs: string, desc: string, buf?: integer }[]
function M.clear(installed)
	for _, k in ipairs(installed) do
		-- get_keymap reports the notation form (`<C-H>`, `<lt>`) for special keys, so compare termcoded bytes, not
		-- spellings; otherwise a trigger on `<C-h>` survives a rebuild and keeps loading the old plan's plugin.
		local want = vim.api.nvim_replace_termcodes(k.lhs, true, true, true)
		local maps
		if not k.buf then
			maps = vim.api.nvim_get_keymap(k.mode)
		elseif vim.api.nvim_buf_is_valid(k.buf) then
			maps = vim.api.nvim_buf_get_keymap(k.buf, k.mode)
		else
			maps = {}
		end
		for _, km in ipairs(maps) do
			if vim.api.nvim_replace_termcodes(km.lhs, true, true, true) == want and km.desc == k.desc then
				del_map(k.mode, k.lhs, k.buf)
				break
			end
		end
	end
end

return M
