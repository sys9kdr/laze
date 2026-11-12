--- Trigger-time behavior, required at the first fire rather than at plan build: none of this runs on a startup that
--- never hits a trigger (docs/performance.md). Everything these bodies need is an explicit argument, so the plan's
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
-- FileType handler would otherwise miss the buffer). Guarded against dispatcher re-entry.
local refiring = {}
---@param event string
---@param exec_opts table
function M.refire(event, exec_opts)
	if refiring[event] then
		return
	end
	refiring[event] = true
	exec_opts.modeline = false
	pcall(vim.api.nvim_exec_autocmds, event, exec_opts)
	refiring[event] = nil
end

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
	for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = event })) do
		local name = autocmd.group_name
		if name and not exclude[name] and not done[name] then
			done[name] = true
			M.refire(event, { group = name, buffer = ev.buf, data = ev.data })
		end
	end
end

--- One bucket of `(event, pattern)` variants; only this event's routes load.
---@param ev table
---@param bucket_routes { event: string, ids: string[] }[]
---@param load fun(id: string): boolean
function M.event(ev, bucket_routes, load)
	local exclude = snapshot_groups(ev.event)
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
		if ev.event == "FileType" then
			M.refire(ev.event, { buffer = ev.buf, data = ev.data })
		else
			replay_groups(ev.event, ev, exclude)
		end
	end
end

---@param ev table
---@param ids string[]
---@param load fun(id: string): boolean
function M.ft(ev, ids, load)
	local loaded_any = false
	for _, id in ipairs(ids) do
		if load(id) then
			loaded_any = true
		end
	end
	-- Re-fire only if something loaded: its handlers missed the natural pass. Otherwise every matching handler
	-- already saw this FileType.
	if loaded_any then
		M.refire("FileType", { buffer = ev.buf })
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
		-- get_keymap reports the leader-expanded lhs; expand likewise.
		local want = vim.api.nvim_replace_termcodes(k.lhs, true, false, true)
		local maps
		if not k.buf then
			maps = vim.api.nvim_get_keymap(k.mode)
		elseif vim.api.nvim_buf_is_valid(k.buf) then
			maps = vim.api.nvim_buf_get_keymap(k.buf, k.mode)
		else
			maps = {}
		end
		for _, km in ipairs(maps) do
			if km.lhs == want and km.desc == k.desc then
				del_map(k.mode, k.lhs, k.buf)
				break
			end
		end
	end
end

return M
