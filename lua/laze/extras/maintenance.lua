--- Maintenance helpers for `:Laze` and direct callers. Every function resolves the last setup lazily.

local M = {}

---@return table<string, boolean>?
local function desired_pkgs()
	local laze = require("laze")
	local specs = laze.get_specs()
	if not specs then
		return nil
	end
	local set = {}
	for _, s in ipairs(laze.compile(specs).pack) do
		set[s.name] = true
	end
	return set
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

--- Installed plugins with the fields `clean` needs. `info = false` skips the
--- per-plugin `git branches/tags` spawn in `vim.pack.get()` (unused here).
---@return { name: string, path: string, active: boolean }[]
local function installed_plugins()
	local plugins = {}
	for _, p in ipairs(vim.pack.get(nil, { info = false })) do
		plugins[#plugins + 1] = { name = p.spec.name, path = p.path, active = p.active }
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
	---@type table<string, boolean>
	local active = {}
	for _, p in ipairs(installed_plugins()) do
		if p.path ~= self and not desired[p.name] then
			stale[#stale + 1] = p.name
			active[p.name] = p.active
		end
	end
	table.sort(stale)
	if #stale == 0 then
		vim.notify("laze: clean — every managed plugin is in the spec list")
		return stale
	end

	-- `vim.pack.del` refuses plugins active in this session; handing them over
	-- makes it delete the rest and then throw.
	---@type string[]
	local deletable = {}
	---@type string[]
	local blocked = {}
	for _, name in ipairs(stale) do
		if active[name] then
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
	return stale
end

function M.health()
	local laze = require("laze")
	local specs = laze.get_specs()
	if not specs then
		vim.notify("laze: health: no setup has run yet", vim.log.levels.WARN)
		return
	end
	local compiled = laze.compile(specs)
	local data_dir = vim.fn.stdpath("data")
	local lines = {}
	for id, entry in pairs(compiled.registry) do
		local installed = entry.dir and vim.fn.isdirectory(entry.dir) == 1
			or (entry.pkg and #vim.fn.glob(data_dir .. "/site/pack/*/opt/" .. entry.pkg, false, true) > 0)
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
