---@class LazeKeySpecBase
---@field mode? string|string[]
---@field desc? string
---@field silent? boolean

---@class LazeKeySpec: LazeKeySpecBase
---@field [1] string lhs
---@field [2]? string|fun()

---@class LazeNamedKeySpec: LazeKeySpecBase
---@field lhs string lhs
---@field rhs? string|fun()

---@class LazeSpec
---@field [1] string
---@field name? string
---@field dir? string
---@field url? string
---@field event? string|string[]
---@field ft? string|string[]
---@field cmd? string|string[]
---@field keys? string|(string|LazeKeySpec|LazeNamedKeySpec)[]
---@field dev? boolean|string
---@field dev_path? string
---@field version? string|false Semver range; git refs use branch/tag/commit
---@field data? any
---@field branch? string
---@field tag? string
---@field commit? string
---@field pin? boolean
---@field build? string|fun()|false
---@field module? string|string[]|false
---@field main? string
---@field opts? table
---@field init? fun()
---@field config? fun()
---@field cond? fun(): boolean|boolean
---@field enabled? fun(): boolean|boolean
---@field lazy? boolean Explicit eager/lazy override (lazy.nvim semantics)
---@field silent? boolean
---@field priority? number
---@field after? string[]

---@class LazeCompiled
---@field pack vim.pack.Spec[]
---@field registry table<string, LazeEntry>
---@field routes LazeRoutes

---@class LazeEntry
---@field id string
---@field src string
---@field dir? string Local dir plugin path (excluded from pack; loaded via :packadd)
---@field module? string|string[]
---@field main? string Module for opts (explicit; never guessed)
---@field opts? table Passed to require(main).setup(opts) at load
---@field init? fun()
---@field config? fun()
---@field cond? fun(): boolean
---@field enabled boolean
---@field silent boolean
---@field after? string[]
---@field dev_path? string
---@field build? string|fun()
---@field priority? number
---@field lazy? boolean Explicit lazy.nvim override (nil = infer from triggers/deps)
---@field has_route boolean Plugin has at least one lazy-load trigger
---@field is_dep boolean Plugin is referenced as an `after` dependency (never eager)
---@field eager boolean Plugin is loaded at startup (compile's shared eager decision)
---@field pkg? string Directory name under pack/<pkg>/opt/ (matches vim.pack; may differ from id for dotted repos)

---@class LazeKeyRoute One trigger map for a single (lhs, mode) variant
---@field mode string Normalized single mode (mode arrays are expanded at compile time)
---@field ids string[]
---@field rhs? string|fun()
---@field desc? string
---@field silent? boolean

---@class LazeRoutes
---@field events table<string, {ids: string[], pattern?: string}[]> One pattern variant per distinct (event, pattern) pair
---@field fts table<string, string[]>
---@field cmds table<string, string[]>
---@field keys table<string, LazeKeyRoute[]> Keyed by lhs; one entry per mode variant
---@field modules table<string, string[]>

---@alias LazePlan fun(): nil

local _compile = require("laze.compile")
local plan = require("laze.plan")

local M = {}

-- The last setup's specs/opts, kept so reload_all() can rebuild the plan.
-- Documented module-level state — the one exception to the closure-local
-- rule below ("No global state" in AGENTS.md). The plan itself stays
-- closure-local; this only remembers what to re-run.
local last_setup = nil

---@param specs LazeSpec[]
---@param opts? { dev_root?: string }
---@return LazeCompiled
function M.compile(specs, opts)
	return _compile.compile(specs, opts)
end

---@param compiled LazeCompiled
---@param opts? { on_load?: fun(id: string, time_ms: number), on_fail?: fun(id: string, err: string) }
---@return LazePlan
function M.build_plan(compiled, opts)
	return plan.build_plan(compiled, opts)
end

---@param specs LazeSpec[]
---@param opts? { dev_root?: string, on_load?: fun(id: string, time_ms: number), on_fail?: fun(id: string, err: string) }
---@return LazeCompiled
function M.setup(specs, opts)
	opts = opts or {}
	local compiled = _compile.compile(specs, opts)

	-- vim.pack has no build concept: subscribe to PackChanged and execute
	-- the spec's `build` after install/update (lazy.nvim-compatible).
	-- The augroup MUST be registered before vim.pack.add below: PackChanged
	-- fires synchronously inside add() for a fresh install, so a late
	-- subscription would silently skip every first build.
	local builds = {}
	for id, entry in pairs(compiled.registry) do
		if entry.build and entry.pkg then
			-- Key by the PACK name (entry.pkg): PackChanged delivers
			-- data.spec.name, which is the pack entry name — identical to
			-- the registry id only for undotted repos (which-key.nvim has
			-- id "which-key" but pack name "which-key.nvim").
			builds[entry.pkg] = entry.build
		end
	end
	if next(builds) then
		vim.api.nvim_create_autocmd("PackChanged", {
			group = vim.api.nvim_create_augroup("laze_build", { clear = true }),
			callback = function(ev)
				local data = ev.data
				if data.kind ~= "install" and data.kind ~= "update" then
					return
				end
				local build = builds[data.spec.name]
				if not build then
					return
				end
				-- Fresh installs are not on the runtimepath (no-op load
				-- fun); activate before running the build so plugins like
				-- treesitter's :TSInstallSelf work. Use :packadd! during
				-- startup to avoid double-sourcing with the plugin phases.
				if data.kind == "install" and not data.active then
					if vim.v.vim_did_enter == 0 then
						pcall(vim.cmd, "packadd! " .. vim.fn.fnameescape(data.spec.name))
					else
						pcall(vim.cmd.packadd, data.spec.name)
					end
				end
				local run = function()
				if type(build) == "function" then
					local ok, err = pcall(build)
					if not ok then
						vim.notify(
							("laze: build failed for %s: %s"):format(data.spec.name, tostring(err)),
							vim.log.levels.WARN
						)
					end
				elseif build:sub(1, 1) == ":" then
					pcall(vim.cmd, build)
				else
					local result = vim.system({ "sh", "-c", build }, { cwd = data.path }):wait()
					if result.code ~= 0 then
						vim.notify(
							("laze: build failed for %s (exit %d): %s"):format(
								data.spec.name,
								result.code,
								result.stderr or ""
							),
							vim.log.levels.WARN
						)
					end
				end
			end
			local ok = pcall(run)
			if not ok then
				vim.notify(
					("laze: build failed for %s: %s"):format(data.spec.name, "error in build hook"),
					vim.log.levels.WARN
				)
			end
		end,
		})
	end

	-- Split activation responsibility: eager plugins (compile's `eager`
	-- flag: no trigger and not a dependency, unless `lazy` overrides) get the
	-- runtimepath entry at setup (:packadd! via `load = false`) so the
	-- startup plugin/ and after/plugin phases source their files — their
	-- init/config still run via the plan. Lazy plugins get a no-op `load`
	-- fun: never on the runtimepath until the plan activates them on demand.
	-- A plain add() would :packadd everything, defeating lazy loading.
	-- Pack specs carry the directory name (`pkg`), which can differ from
	-- the registry id for dotted repos — map back via pkg.
	local pkg_to_id = {}
	for id, entry in pairs(compiled.registry) do
		if entry.pkg then
			pkg_to_id[entry.pkg] = id
		end
	end
	local eager_pack = {}
	local lazy_pack = {}
	for _, spec in ipairs(compiled.pack) do
		local entry = compiled.registry[pkg_to_id[spec.name]]
		if entry.eager then
			table.insert(eager_pack, spec)
		else
			table.insert(lazy_pack, spec)
		end
	end
	if #eager_pack > 0 then
		vim.pack.add(eager_pack, { load = false })
	end
	if #lazy_pack > 0 then
		vim.pack.add(lazy_pack, { load = function() end })
	end

	plan.build_plan(compiled, opts)()
	last_setup = { specs = specs, opts = opts }
	return compiled
end

--- Specs from the last setup() call (for opt-in extras like LazeClean).
--- Read-only view: do not mutate the returned table.
---@return LazeSpec[]?
function M.get_specs()
	return last_setup and last_setup.specs or nil
end

--- Re-run the last setup() call: re-compile, re-add to vim.pack
--- (idempotent for existing installs), rebuild all triggers and run a
--- fresh plan. Eager plugins re-load with a fresh `loaded` state, so
--- their init/config callbacks and plugin files run again — treat it as
--- a restart of the plugin stack. Intended for dev loops: edit files in
--- a dev clone, call reload_all() (or bind it to a command).
---@param new_specs? LazeSpec[] Optional override; defaults to the last setup() specs
---@return LazeCompiled
function M.reload_all(new_specs)
	if not last_setup and not new_specs then
		vim.notify("laze: reload_all: no setup has run yet", vim.log.levels.WARN)
		return nil
	end
	if new_specs then
		return M.setup(new_specs)
	end
	return M.setup(last_setup.specs, last_setup.opts)
end

return M
