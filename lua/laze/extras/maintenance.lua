--- Maintenance helpers for `:Laze` and direct callers. Every function resolves the last setup lazily.

local M = {}

--- Reuse the last setup's compile: recompiling would repeat its diagnostics (known differences, unsupported fields).
---@return table<string, boolean>?
local function desired_pkgs()
	local compiled = require("laze").get_compiled()
	if not compiled then
		return nil
	end
	local set = {}
	for _, s in ipairs(compiled.pack) do
		set[s.name] = true
	end
	return set
end

-- Vim's glob magic for one literal path segment; mirrors plan.lua. Neovim has no globescape().
---@param segment string
---@return string
local function glob_escape(segment)
	return (segment:gsub("[\\%[%]{}*?]", "\\%0"))
end

--- Directory of the plugin that provides this module, or nil when laze is not
--- loaded from a `lua/laze/...` tree (e.g. a single-file bundle).
--- `clean` never proposes deleting it: the running copy cannot be removed while
--- it is running, and removing the on-disk copy under it is never wanted.
---@return string?
local function self_dir()
	local source = debug.getinfo(1, "S").source
	if source:sub(1, 1) ~= "@" then
		return nil
	end
	return source:sub(2):match("^(.*)/lua/laze/extras/maintenance%.lua$")
end

--- Lockfile `vim.pack` records its managed plugins in. Nightlies expose it as
--- 'packlockfile', but `vim.pack` caches the path on its first use, so prefer
--- the cached one: reading a different file than `vim.pack` would invent
--- orphans when the option changes mid-session. 0.12 hardcodes the config path.
---@return string
local function lockfile_path()
	---@diagnostic disable-next-line: undefined-field
	local cached = vim.pack._plugin_lock_path
	if type(cached) == "string" and cached ~= "" then
		return cached
	end
	local ok, path = pcall(function()
		---@diagnostic disable-next-line: undefined-field
		return vim.go.packlockfile
	end)
	if ok and type(path) == "string" and path ~= "" then
		return path
	end
	return vim.fs.joinpath(vim.fn.stdpath("config"), "nvim-pack-lock.json")
end

--- Plugin names recorded in the lockfile. `vim.pack.get()` can hide an entry
--- for a whole session (see `installed_plugins`), so orphan detection also reads
--- the file. A missing or unreadable lockfile yields `{}`: detection must not
--- turn a broken file into an error.
---@return string[]
local function lockfile_names()
	local ok_read, lines = pcall(vim.fn.readfile, lockfile_path())
	if not ok_read then
		return {}
	end
	local ok_json, lock = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not ok_json or type(lock) ~= "table" or type(lock.plugins) ~= "table" then
		return {}
	end
	local names = {}
	for name in pairs(lock.plugins) do
		if type(name) == "string" then
			names[#names + 1] = name
		end
	end
	return names
end

--- Installed plugins with the fields `clean` needs. `info = false` skips the
--- per-plugin `git branches/tags` spawn in `vim.pack.get()` (unused here).
--- Lockfile entries `get()` omits are included with `hidden = true`: when the
--- startup install of a lockfile-only plugin fails or is declined, `vim.pack`
--- drops it from its in-memory lock without rewriting the file (neovim#42971),
--- so `get()` would otherwise bless an orphan the lockfile still has.
--- Stopgap for that upstream bug: drop the union once the supported Neovim
--- minimum has the fix (#83).
---@return { name: string, path: string?, active: boolean, hidden?: boolean }[]
local function installed_plugins()
	local plugins = {}
	local seen = {}
	for _, p in ipairs(vim.pack.get(nil, { info = false })) do
		seen[p.spec.name] = true
		plugins[#plugins + 1] = { name = p.spec.name, path = p.path, active = p.active }
	end
	for _, name in ipairs(lockfile_names()) do
		if not seen[name] then
			seen[name] = true
			plugins[#plugins + 1] = { name = name, path = nil, active = false, hidden = true }
		end
	end
	return plugins
end

function M.update()
	vim.pack.update()
end

---@param bang? boolean
---@return string[]? stale names, or nil when no setup has run yet
function M.clean(bang)
	local desired = desired_pkgs()
	if not desired then
		vim.notify("laze: clean: no setup has run yet", vim.log.levels.WARN)
		return nil
	end
	local self = self_dir()
	---@type string[]
	local stale = {}
	---@type table<string, { active: boolean, hidden: boolean }>
	local state = {}
	for _, p in ipairs(installed_plugins()) do
		if p.path ~= self and not desired[p.name] then
			stale[#stale + 1] = p.name
			state[p.name] = { active = p.active, hidden = p.hidden == true }
		end
	end
	table.sort(stale)
	if #stale == 0 then
		vim.notify("laze: clean — every managed plugin is in the spec list")
		return stale
	end

	-- `vim.pack.del` refuses two kinds here, and both make it delete the rest
	-- of the list before throwing: plugins active in this session, and entries
	-- vim.pack dropped from its in-memory lock after a failed or declined
	-- startup install (the lockfile still names them; neovim/neovim#42971).
	---@type string[]
	local deletable = {}
	---@type string[]
	local blocked = {}
	---@type string[]
	local invisible = {}
	for _, name in ipairs(stale) do
		if state[name].hidden then
			invisible[#invisible + 1] = name
		elseif state[name].active then
			blocked[#blocked + 1] = name
		else
			deletable[#deletable + 1] = name
		end
	end

	if not bang then
		local lines = {
			("laze: %d unmanaged plugin(s), clean! to remove:"):format(#stale),
			table.concat(stale, "\n"),
		}
		if #blocked > 0 then
			lines[#lines + 1] = ("active this session (restart before deleting): " .. table.concat(blocked, ", "))
		end
		if #invisible > 0 then
			lines[#lines + 1] = (
				"in the lockfile but not installed this session (neovim/neovim#42971; clean! cannot remove them): "
				.. table.concat(invisible, ", ")
			)
		end
		vim.notify(table.concat(lines, "\n"))
		return stale
	end

	if #deletable > 0 then
		local ok, err = pcall(vim.pack.del, deletable)
		if not ok then
			vim.notify(("laze: clean: %s"):format(err), vim.log.levels.WARN)
		end
	end
	if #blocked > 0 then
		vim.notify(
			("laze: %d active plugin(s) not deleted (restart first):\n%s"):format(#blocked, table.concat(blocked, "\n")),
			vim.log.levels.WARN
		)
	end
	if #invisible > 0 then
		vim.notify(
			("laze: %d lockfile plugin(s) not deleted: vim.pack dropped them this session (neovim/neovim#42971)\n%s"):format(
				#invisible,
				table.concat(invisible, "\n")
			),
			vim.log.levels.WARN
		)
	end
	return stale
end

function M.health()
	local compiled = require("laze").get_compiled()
	if not compiled then
		vim.notify("laze: health: no setup has run yet", vim.log.levels.WARN)
		return
	end
	local data_dir = vim.fn.stdpath("data")
	local lines = {}
	for id, entry in pairs(compiled.registry) do
		local installed = entry.dir and vim.fn.isdirectory(entry.dir) == 1
			or (
				entry.pkg
				and #vim.fn.glob(glob_escape(data_dir .. "/site/pack/") .. "*/opt/" .. glob_escape(entry.pkg), false, true)
					> 0
			)
		lines[#lines + 1] = ("%-30s %s %s"):format(
			id,
			installed and "installed" or "MISSING",
			entry.has_route and "lazy" or "eager"
		)
	end
	table.sort(lines)
	table.insert(lines, 1, ("laze: %d plugin(s)"):format(#lines))
	vim.notify(table.concat(lines, "\n"))
end

function M.reload()
	require("laze").reload_all()
end

return M
