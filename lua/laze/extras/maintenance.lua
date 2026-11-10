--- Maintenance helpers for `:Laze` and direct callers. Never registers
--- commands; every function resolves the last setup lazily.

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

local function installed_names()
	local names = {}
	for _, p in ipairs(vim.pack.get()) do
		names[#names + 1] = p.name
	end
	return names
end

--- Update managed plugins (vim.pack.update).
function M.update()
	vim.pack.update()
end

--- List managed plugins missing from the last setup (dry-run).
--- With `bang`, delete them via vim.pack.del instead.
---@param bang? boolean
---@return string[]? stale names, or nil when no setup has run yet
function M.clean(bang)
	local desired = desired_pkgs()
	if not desired then
		vim.notify("laze: clean: no setup has run yet", vim.log.levels.WARN)
		return nil
	end
	local stale = {}
	for _, name in ipairs(installed_names()) do
		if not desired[name] then
			table.insert(stale, name)
		end
	end
	table.sort(stale)
	if #stale == 0 then
		vim.notify("laze: clean — every managed plugin is in the spec list")
		return stale
	end
	if bang then
		vim.pack.del(stale)
	else
		vim.notify(("laze: %d unmanaged plugin(s), clean(true) to delete:\n%s"):format(#stale, table.concat(stale, "\n")))
	end
	return stale
end

--- Report setup/compile/install state per plugin.
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

--- Re-run the last setup() (dev loop).
function M.reload()
	require("laze").reload_all()
end

return M
