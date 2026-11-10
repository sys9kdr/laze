-- Accepted perf items: docs/performance.md.

-- Module-level so a rebuilt plan clears the previous plan's preload entries instead of stacking stale trigger closures.
local installed_preloads = {}

-- { { mode, lhs, desc, buf? } }. Module-level for the same reason; desc-guarded deletion lets a plugin map
-- that took over the lhs survive a rebuild.
local installed_keys = {}

--- See docs/rtp-index.md.
---@param data_dir string
---@return table<string, string>
local function build_rtp_index(data_dir)
	local index = {}
	local entries = vim.api.nvim_list_runtime_paths()
	local suffix = "/site/pack/"
	for i = 1, #entries do
		local p = entries[i]
		if p:sub(1, #data_dir) == data_dir then
			local pack_name, dir_pkg = p:match("^([^/]+)/opt/(.+)$", #data_dir + #suffix + 1)
			if pack_name and (not index[dir_pkg] or p < index[dir_pkg]) then
				index[dir_pkg] = p
			end
		end
	end
	return index
end

--- The plugin table handed to `init` and `cond` (lazy.nvim passes its
--- LazyPlugin). Only pre-install fields are meaningful.
---@param id string
---@param entry LazeEntry
---@param data_dir string
---@return table
local function plugin_view(id, entry, data_dir)
	return {
		name = id,
		dir = entry.dir or (entry.pkg and (data_dir .. "/site/pack/core/opt/" .. entry.pkg)),
		url = entry.src,
		lazy = not entry.eager,
	}
end

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

--- Resolve `enabled`/`cond` once per session, like lazy.nvim. setup() resolves
--- them before vim.pack.add so a false verdict also skips installation.
---@param registry table<string, LazeEntry>
---@param data_dir string
---@return table<string, boolean> enabled_ok
---@return table<string, boolean> cond_ok
local function resolve_verdicts(registry, data_dir)
	-- A throwing hook is contained as a warning and treated as false. Only `cond` receives the plugin argument.
	local function verdict(value, hook, id, entry)
		if type(value) ~= "function" then
			return value ~= false
		end
		local ok, res
		if entry then
			ok, res = pcall(value, plugin_view(id, entry, data_dir))
		else
			ok, res = pcall(value)
		end
		if not ok then
			require("laze.diag").warn(("%s hook failed for %s: %s"):format(hook, id, tostring(res)))
			return false
		end
		return res ~= false
	end

	local enabled_ok, cond_ok = {}, {}
	for id, entry in pairs(registry) do
		enabled_ok[id] = verdict(entry.enabled, "enabled", id)
		cond_ok[id] = verdict(entry.cond, "cond", id, entry)
	end
	return enabled_ok, cond_ok
end

---@param entry LazeEntry
---@return string[]?
local function modules_array(entry)
	local m = entry.module
	if type(m) == "string" then
		return { m }
	end
	return type(m) == "table" and m or nil
end

---@param compiled LazeCompiled
---@param opts? { on_load?: fun(id: string, time_ms: number), on_fail?: fun(id: string, err: string), enabled_ok?: table<string, boolean>, cond_ok?: table<string, boolean> }
---@return LazePlan
local function build_plan(compiled, opts)
	opts = opts or {}
	local on_load = opts.on_load
	local on_fail = opts.on_fail
	local registry = compiled.registry
	local routes = compiled.routes
	-- Resolved once: it cannot change during a plan.
	local data_dir = vim.fn.stdpath("data")
	-- Lazy pkg -> opt dir cache. Invalidated by this plan's only 'runtimepath' mutations (the dir prepend and the
	-- `:packadd!` fallback). A miss is always safe; closure-local because reload_all() rebuilds it. See
	-- docs/rtp-index.md.
	local rtp_index = nil
	local loaded = {}
	local startup_pending = {}
	local startup_pending_order = {}
	local startup_finalizer_installed = false
	local startup_cmd_calls = {}
	-- Inside a startup plugin.load(), a dependency loads with its dependent instead of deferring to VimEnter: lazy.nvim
	-- recurses into deps within load(), so a non-lazy dep is configured before the eager plugin (measured at 306a055).
	local eager_depth = 0

	-- Neovim sources every 'runtimepath' plugin/ dir when its startup phase begins. Packs activated before that are
	-- sourced by Neovim; later ones by the VimEnter finalizer. This tracks the handover.
	local startup_plugin_phase_started = false
	if vim.v.vim_did_enter == 0 then
		local group = vim.api.nvim_create_augroup("laze_startup_phase", { clear = true })
		vim.api.nvim_create_autocmd("SourcePre", {
			group = group,
			callback = function(ev)
				-- Plain finds keep this out of trace aborts: 286 -> 37 ns per
				-- event (tests/benchmarks/jit_ab.lua WORKLOAD=probe).
				local m = ev.match
				if m:find("/plugin/", 1, true) or m:find("\\plugin\\", 1, true) then
					startup_plugin_phase_started = true
					return true -- delete this autocmd
				end
			end,
		})
	end

	-- Unresolved here for direct build_plan callers; setup() pre-resolves (see resolve_verdicts).
	local enabled_ok, cond_ok = opts.enabled_ok, opts.cond_ok
	if not (enabled_ok and cond_ok) then
		local e, c = resolve_verdicts(registry, data_dir)
		enabled_ok = enabled_ok or e
		cond_ok = cond_ok or c
	end

	-- Pin it: plugin code or another manager may replace _G.require later.
	local original_require = require

	-- `:packadd` sources plugin/ and ftdetect/ but not after/plugin (startup only), so post-startup loads need this.
	-- Sorted to match the startup after/plugin phase.
	local function source_after_plugin(dir)
		local files = vim.fn.glob(dir .. "/after/plugin/**/*.{lua,vim}", false, true)
		table.sort(files)
		for _, file in ipairs(files) do
			pcall(vim.cmd.source, file)
		end
	end

	local function source_glob(dir, pattern)
		for _, file in ipairs(vim.fn.glob(dir .. pattern, false, true)) do
			pcall(vim.cmd.source, file)
		end
	end

	-- Re-fire the triggering event after a load so autocmds the plugin registers while loading see it (an ft plugin's
	-- FileType handler would otherwise miss the buffer). Guarded against dispatcher re-entry.
	local refiring = {}
	local function refire_event(event, exec_opts)
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
	local function snapshot_event_groups(event)
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
	local function replay_event_groups(event, ev, exclude)
		local done = {}
		for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ event = event })) do
			local name = autocmd.group_name
			if name and not exclude[name] and not done[name] then
				done[name] = true
				refire_event(event, { group = name, buffer = ev.buf, data = ev.data })
			end
		end
	end

	--- lazy.nvim opts resolution at load time: a function gets the plugin and a mutable base; a table return replaces it,
	--- a non-table return is wrapped, nil keeps the base.
	---@param entry LazeEntry
	---@param plugin table
	---@return table
	local function resolve_opts(entry, plugin)
		local entry_opts = entry.opts
		if type(entry_opts) == "function" then
			local base = {}
			local res = entry_opts(plugin, base)
			if type(res) == "table" then
				return res
			elseif res then
				return { res }
			end
			return base
		end
		return type(entry_opts) == "table" and entry_opts or {}
	end

	-- `partial` runs the hooks but keeps the plugin pending_startup, for a startup require() that needs a configured
	-- plugin now. Hooks run once; the VimEnter finalizer then only marks it loaded.
	local function run_hooks(id, entry, start, plugin_dir, hook_opts)
		local function mark_failed(err)
			loaded[id] = "failed"
			if not entry.silent then
				require("laze.diag").warn("failed to load " .. id .. ": " .. tostring(err))
			end
		end
		local plugin = {
			name = id,
			dir = plugin_dir or entry.dir,
			url = entry.src,
			pkg = entry.pkg,
			main = entry.main,
			opts = entry.opts,
			lazy = not entry.eager,
		}
		local pending = startup_pending[id]
		if pending and pending.hooks_ran then
			if not (hook_opts and hook_opts.partial) then
				loaded[id] = true
				if on_load and start then
					on_load(id, (vim.uv.hrtime() - start) / 1e6)
				end
			end
			return
		end
		if pending and hook_opts and hook_opts.partial then
			local plugin_modules = modules_array(entry)
			local ok, err = pcall(function()
				if plugin_modules then
					for _, mod in ipairs(plugin_modules) do
						original_require(mod)
					end
				end
				if entry.config then
					entry.config(plugin, resolve_opts(entry, plugin))
				end
			end)
			if not ok then
				mark_failed(err)
			else
				pending.hooks_ran = true
			end
			return
		end
		local plugin_modules = modules_array(entry)
		if plugin_modules then
			local ok_req, err_req = pcall(function()
				for _, mod in ipairs(plugin_modules) do
					original_require(mod)
				end
			end)
			if not ok_req then
				mark_failed(err_req)
				if on_fail then
					on_fail(id, err_req)
				end
				return
			end
		end
		if entry.config then
			local ok_cfg, err_cfg = pcall(function()
				entry.config(plugin, resolve_opts(entry, plugin))
			end)
			if not ok_cfg then
				require("laze.diag").warn("config failed for " .. id .. ": " .. tostring(err_cfg))
			end
		end
		if pending then
			pending.hooks_ran = true
		end
		loaded[id] = true
		if on_load and start then
			on_load(id, (vim.uv.hrtime() - start) / 1e6)
		end
	end

	local function finalize_startup_pending()
		local ft_ids = routes.fts[vim.bo.filetype]
		local finalized_ft = false
		for _, id in ipairs(startup_pending_order) do
			local pending = startup_pending[id]
			if pending and loaded[id] == "pending_startup" then
				-- `:packadd!` left these unsourced. Packs present before Neovim's startup plugin/ phase are sourced by it; only
				-- late additions need manual sourcing.
				if pending.dir and pending.source_later then
					source_glob(pending.dir, "/plugin/**/*.{lua,vim}")
					source_glob(pending.dir, "/ftdetect/*.vim")
					source_after_plugin(pending.dir)
				end
				run_hooks(id, pending.entry, pending.start, pending.dir)
				if ft_ids then
					for _, ft_id in ipairs(ft_ids) do
						if ft_id == id then
							finalized_ft = true
						end
					end
				end
			end
		end
		-- Finalized ft plugins registered their autocmds during finalization; re-fire FileType so they see the current
		-- buffer. Only when one was actually finalized: otherwise its handlers already saw this event.
		if finalized_ft then
			refire_event("FileType", { buffer = vim.api.nvim_get_current_buf() })
		end
	end

	local function load_plugin(id)
		if loaded[id] then
			return
		end

		local entry = registry[id]
		if not entry then
			return
		end
		if not enabled_ok[id] then
			return
		end
		if not cond_ok[id] then
			return
		end

		local start = on_load and vim.uv.hrtime() or nil
		loaded[id] = true

		-- Activation: make plugin/, ftdetect/ and after/plugin/ reachable. During startup, Neovim's own phases source them,
		-- so only add the dir to 'runtimepath' (`:packadd!`); a full `:packadd` would source plugin/ a second time. After
		-- startup `:packadd` sources plugin/ and ftdetect/; after/plugin/ is sourced manually.
		local during_startup = vim.v.vim_did_enter == 0
		local plugin_dir
		if entry.dir then
			-- Add local dirs by exact path. Never `:packadd`: it resolves by basename across 'packpath', so a stale install
			-- sharing the name wins and the user's dir is silently skipped (issue: module not found with no hint).
			vim.opt.rtp:prepend(entry.dir)
			rtp_index = nil -- rtp mutated: rebuild the fast-path index on next use
			if not during_startup then
				-- Nothing else sources these post-startup, so commands, maps and filetype detection would never exist.
				source_glob(entry.dir, "/plugin/**/*.{lua,vim}")
				source_glob(entry.dir, "/ftdetect/*.vim")
			end
			plugin_dir = entry.dir
		else
			-- Packs live in pack/<pkg>/opt/<pkg>; `:packadd` addresses the directory name (entry.pkg), which can differ from
			-- the id ("which-key" vs "which-key.nvim"). Startup fast path: setup() already activated eager plugins with
			-- `vim.pack.add(..., { load = false })` (`:packadd!`, no sourcing), so a dir already on 'runtimepath' needs
			-- neither the glob nor the redundant `:packadd!`. Post-startup this must not apply: plain `:packadd` is what
			-- sources plugin/.
			if during_startup then
				rtp_index = rtp_index or build_rtp_index(data_dir)
				plugin_dir = rtp_index[entry.pkg]
			end
			if not plugin_dir then
				local found = vim.fn.glob(data_dir .. "/site/pack/*/opt/" .. entry.pkg, false, true)
				plugin_dir = found[1]
				if plugin_dir then
					local cmd = during_startup and "packadd! " or "packadd "
					pcall(vim.cmd, cmd .. vim.fn.fnameescape(entry.pkg))
					rtp_index = nil
				end
			end
		end

		-- Inside an eager plugin's startup load (issue #42): deferring this
		-- dependency to VimEnter would configure the parent before it.
		if during_startup and eager_depth == 0 and not entry.eager then
			loaded[id] = "pending_startup"
			startup_pending[id] = {
				entry = entry,
				dir = plugin_dir,
				start = start,
				hooks_ran = false,
				source_later = startup_plugin_phase_started,
			}
			table.insert(startup_pending_order, id)
			if not startup_finalizer_installed then
				startup_finalizer_installed = true
				vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = finalize_startup_pending })
			end
			return
		end

		-- after/plugin/ never runs on `:packadd`: post-startup loads source it manually; startup loads get it from the
		-- startup phase (sourcing it twice would double-execute).
		if not during_startup and plugin_dir then
			source_after_plugin(plugin_dir)
		end

		run_hooks(id, entry, start, plugin_dir)
	end

	local function load_with_deps(id)
		-- Any assigned state means already processed or deferred.
		if loaded[id] then
			return
		end

		local root_entry = registry[id]
		if not (root_entry and root_entry.after and root_entry.after[1]) then
			load_plugin(id)
			return
		end

		-- Iterative DFS; each level tracks a dependency cursor. A node is popped only after load_plugin runs, so
		-- backtracking always reaches unprocessed nodes. Cycle detection scans the current path.
		local stack = { id }
		local cursor = { 1 }
		local depth = 1

		while depth > 0 do
			local current = stack[depth]
			local entry = registry[current]
			local deps = entry and entry.after or {}
			local i = cursor[depth]
			if i <= #deps then
				cursor[depth] = i + 1
				local dep = deps[i]
				if not loaded[dep] then
					local has_cycle = false
					for j = 1, depth do
						if stack[j] == dep then
							require("laze.diag").warn(("cycle in after deps (%s)"):format(dep))
							has_cycle = true
							break
						end
					end
					-- Skip only the cyclic dep (the cursor already advanced), so sibling deps still load.
					if not has_cycle then
						depth = depth + 1
						stack[depth] = dep
						cursor[depth] = 1
					end
				end
			else
				load_plugin(current)
				depth = depth - 1
			end
		end
	end

	-- Module triggers are package.preload entries, not a _G.require wrapper:
	-- unrelated requires are untouched, nothing global is mutated, and each
	-- entry consumes itself on first require. It must remove the entry before
	-- load_with_deps, because load_plugin re-requires the declared modules
	-- through original_require and would otherwise hit the entry again.
	for name in pairs(installed_preloads) do
		package.preload[name] = nil
		installed_preloads[name] = nil
	end
	for modname, ids in pairs(routes.modules or {}) do
		installed_preloads[modname] = true
		package.preload[modname] = function()
			package.preload[modname] = nil
			installed_preloads[modname] = nil
			-- require holds an in-flight sentinel in package.loaded while this runs; load_plugin's re-require would hit it.
			-- Clear it so the real module loads from rtp.
			package.loaded[modname] = nil
			for _, id in ipairs(ids) do
				load_with_deps(id)
			end
			local mod = original_require(modname)
			for _, id in ipairs(ids) do
				local pending = loaded[id] == "pending_startup" and startup_pending[id]
				if pending and not pending.hooks_ran then
					-- A startup require() needs a configured plugin before it returns. Sourcing stays with the startup phase /
					-- VimEnter finalizer, preserving source-exactly-once.
					run_hooks(id, pending.entry, pending.start, pending.dir, { partial = true })
				end
			end
			return mod
		end
	end

	local init_ran = false
	return function()
		-- lazy.nvim parity: `init` runs once at startup for every enabled plugin whose `cond` passes, before any load.
		-- lazy.nvim's own order is unspecified; sorting by id keeps recompiles deterministic. The plan closure can be
		-- invoked repeatedly, so this pass is one-shot.
		if not init_ran then
			init_ran = true
			local init_ids = {}
			for id, entry in pairs(registry) do
				if entry.init and enabled_ok[id] and cond_ok[id] then
					table.insert(init_ids, id)
				end
			end
			table.sort(init_ids)
			for _, id in ipairs(init_ids) do
				local entry = registry[id]
				local ok_init, err_init = pcall(entry.init, plugin_view(id, entry, data_dir))
				if not ok_init then
					require("laze.diag").warn(("init failed for %s: %s"):format(id, tostring(err_init)))
				end
			end
		end

		-- Keymaps have no group to clear, so delete the previous plan's maps here. Only maps still carrying the trigger
		-- desc: a plugin map that took over the lhs, or a user map sharing it, must survive.
		for _, k in ipairs(installed_keys) do
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
		installed_keys = {}

		-- Groups are recreated unconditionally (clear = true) so a rebuilt
		-- plan with fewer routes drops the predecessor's stale closures.
		local events_group = vim.api.nvim_create_augroup("laze_events", { clear = true })
		local fts_group = vim.api.nvim_create_augroup("laze_fts", { clear = true })
		local cmds_group = vim.api.nvim_create_augroup("laze_cmds", { clear = true })
		-- FileType autocmds installing buffer-local maps for ft-scoped keys.
		local key_fts_group = vim.api.nvim_create_augroup("laze_key_fts", { clear = true })

		-- `User VeryLazy` fires unconditionally (lazy.nvim parity), so user
		-- autocmds keyed on it run even with no spec declaring it.
		vim.api.nvim_create_autocmd("UIEnter", {
			group = vim.api.nvim_create_augroup("laze_verylazy", { clear = true }),
			once = true,
			callback = function()
				vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
			end,
		})

		if next(routes.events) then
			local group = events_group
			-- One autocmd per bucket of (event, pattern) variants, keyed by pattern: one API call per bucket instead of per
			-- event (~1.3 us each). `once` self-deletes per row, so the callback filters on ev.event to load only that
			-- event's ids.
			local buckets = {} ---@type table<string, { pattern?: string, names: string[], routes: {event: string, ids: string[]}[] }>
			local border = {}
			for event, variants in pairs(routes.events) do
				if event == "VeryLazy" then
					-- Synthetic event: lazy.nvim maps VeryLazy to User VeryLazy, emitted by the UIEnter handler above.
					local verylazy_ids = {}
					for _, variant in ipairs(variants) do
						for _, id in ipairs(variant.ids) do
							table.insert(verylazy_ids, id)
						end
					end
					vim.api.nvim_create_autocmd("User", {
						group = group,
						pattern = "VeryLazy",
						once = true,
						callback = function()
							for _, id in ipairs(verylazy_ids) do
								load_with_deps(id)
							end
						end,
					})
				else
					for _, variant in ipairs(variants) do
						local key = variant.pattern or ""
						local b = buckets[key]
						if not b then
							b = { pattern = variant.pattern, names = {}, routes = {} }
							buckets[key] = b
							table.insert(border, b)
						end
						table.insert(b.names, event)
						table.insert(b.routes, { event = event, ids = variant.ids })
					end
				end
			end
			for _, b in ipairs(border) do
				vim.api.nvim_create_autocmd(b.names, {
					group = group,
					pattern = b.pattern,
					once = true,
					callback = function(ev)
						-- Snapshot before loading: only this diff separates the new plugin's augroups from pre-existing ones.
						local exclude = snapshot_event_groups(ev.event)
						local loaded_any = false
						for _, route in ipairs(b.routes) do
							if route.event == ev.event then
								for _, id in ipairs(route.ids) do
									local was = loaded[id]
									load_with_deps(id)
									if was ~= true and loaded[id] == true then
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
								refire_event(ev.event, { buffer = ev.buf, data = ev.data })
							else
								replay_event_groups(ev.event, ev, exclude)
							end
						end
					end,
				})
			end
		end

		if next(routes.fts) then
			local group = fts_group
			-- One FileType autocmd for all triggers (per-ft autocmds cost ~15 us each at startup).
			vim.api.nvim_create_autocmd("FileType", {
				group = group,
				pattern = "*",
				callback = function(ev)
					local current_ids = routes.fts[ev.match]
					if current_ids then
						local loaded_any = false
						for _, id in ipairs(current_ids) do
							local was = loaded[id]
							load_with_deps(id)
							if was ~= true and loaded[id] == true then
								loaded_any = true
							end
						end
						-- Re-fire only if something loaded: its handlers missed the natural pass. Otherwise every matching handler
						-- already saw this FileType.
						if loaded_any then
							refire_event("FileType", { buffer = ev.buf })
						end
					end
				end,
			})

			-- A command-line file can get its FileType before init.lua reaches setup(); the FileType autocmd then exists but
			-- the one event it needed already passed. Catch up the current buffer after registering routes. During startup
			-- this stays `:packadd!` only, so Neovim's plugin/ phase keeps its exactly-once sourcing.
			local function load_current_ft()
				local current_ids = routes.fts[vim.bo.filetype]
				if current_ids then
					for _, id in ipairs(current_ids) do
						load_with_deps(id)
					end
				end
			end
			load_current_ft()
			if vim.v.vim_did_enter == 0 then
				-- The buffer can still have no filetype while init.lua runs and receive it late in startup without a usable
				-- FileType callback. Check again once startup completes.
				vim.api.nvim_create_autocmd("VimEnter", {
					group = group,
					once = true,
					callback = load_current_ft,
				})
			end
		end

		if next(routes.cmds) then
			local group = cmds_group
			-- One CmdUndefined autocmd for all triggers (per-cmd autocmds cost ~12 us each at startup). Misfires are rare, so
			-- the O(1) lookup is free.
			vim.api.nvim_create_autocmd("CmdUndefined", {
				group = group,
				pattern = "*",
				callback = function(ev)
					local ids = routes.cmds[ev.match]
					if not ids then
						return
					end
					for _, id in ipairs(ids) do
						load_with_deps(id)
					end
					if vim.v.vim_did_enter == 0 then
						-- Cold: the proxy body is parsed only when a startup command actually misfires (docs/performance.md).
						require("laze.cmdproxy").defer(startup_cmd_calls, ev.match)
					end
				end,
			})
		end

		-- One map per (lhs, mode) variant. compile already expands a `mode`
		-- array, so a takeover below touches only its own mode.
		for lhs, variants in pairs(routes.keys) do
			for _, entry in ipairs(variants) do
				local mode = entry.mode
				local rhs = entry.rhs
				-- A variant whose plugins are all disabled gets no map at all, not even the trigger: lazy.nvim never enables
				-- handlers for a disabled plugin (parity, #30).
				local ids = {}
				for _, id in ipairs(entry.ids) do
					if enabled_ok[id] and cond_ok[id] then
						table.insert(ids, id)
					end
				end
				if #ids > 0 and rhs ~= false then
					local function install(buf)
						local function map_opts(desc)
							local map_options = { desc = desc }
							if entry.silent ~= nil then
								map_options.silent = entry.silent
							end
							if buf then
								map_options.buffer = buf
							end
							return map_options
						end
						if type(rhs) == "string" and (rhs == "" or rhs:lower() == "<nop>") then
							-- lazy.nvim: an empty rhs / <nop> is a static no-op mapping, not a load trigger.
							local key_opts = map_opts(entry.desc)
							vim.keymap.set(mode, lhs, rhs, key_opts)
							table.insert(installed_keys, { mode = mode, lhs = lhs, desc = key_opts.desc, buf = buf })
						else
							local key_opts = map_opts(entry.desc or "laze: load on key")
							table.insert(installed_keys, { mode = mode, lhs = lhs, desc = key_opts.desc, buf = buf })
							vim.keymap.set(mode, lhs, function()
								-- Verdicts were resolved at plan build, so every id here is active.
								if rhs == nil then
									-- Delete the trigger before loading: after the load it would also delete the plugin's fresh map
									-- (vim.keymap.del removes every map for this lhs in the mode). Other mode variants are separate maps
									-- and stay.
									del_map(mode, lhs, buf)
								end
								for _, id in ipairs(ids) do
									load_with_deps(id)
								end
								if rhs == nil then
									-- Replay the key so the plugin's own map handles it. Queue it BEFORE keys already behind the trigger
									-- ('i'): with append, `gcA` would run `A` first and then insert `gc` literally instead of firing
									-- `gcA`.
									vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "i", true)
								elseif type(rhs) == "function" then
									rhs()
								else
									vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(rhs, true, false, true), "i", true)
								end
							end, key_opts)
						end
					end
					if entry.ft then
						-- lazy.nvim installs the buffer-local map only in buffers of the declared filetype(s), and does not
						-- retrofit buffers that already had it.
						vim.api.nvim_create_autocmd("FileType", {
							group = key_fts_group,
							pattern = entry.ft,
							callback = function(ev)
								install(ev.buf)
							end,
						})
					else
						install(nil)
					end
				end
			end
		end

		-- Eager plugins load by `priority` (higher first, default 50), ties by id; spec order is not preserved.
		local eager = {}
		for _, entry in pairs(registry) do
			if enabled_ok[entry.id] and entry.eager then
				table.insert(eager, entry)
			end
		end
		if #eager > 1 then
			table.sort(eager, function(a, b)
				local pa = a.priority or 50
				local pb = b.priority or 50
				if pa ~= pb then
					return pa > pb
				end
				return a.id < b.id
			end)
		end
		for _, entry in ipairs(eager) do
			-- Deps reached here load synchronously with their parent (see the eager_depth note above), matching lazy.nvim's
			-- dep-before-parent config order.
			eager_depth = eager_depth + 1
			local ok, err = pcall(load_with_deps, entry.id)
			eager_depth = eager_depth - 1
			if not ok then
				require("laze.diag").warn(("failed to load %s: %s"):format(entry.id, tostring(err)))
			end
		end

		-- Normally VeryLazy fires through the one-shot UIEnter autocmd. If the plan is built after startup, UIEnter already
		-- fired (or, headless, never will), so fire it now.
		if vim.v.vim_did_enter ~= 0 or #vim.api.nvim_list_uis() == 0 then
			vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
		end
	end
end

return { build_plan = build_plan, resolve_verdicts = resolve_verdicts }
