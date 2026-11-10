local TRIGGER_FIELDS = { "event", "ft", "cmd", "keys" }
local ARRAY_TRIGGER_FIELDS = { "ft", "cmd" }
local SOURCE_FIELDS = { "dir", "url", "name" }
local VERSION_REF_FIELDS = { "branch", "tag", "commit" }
-- lazy.nvim accepts boolean or function for both cond and enabled; lazy and submodules are boolean-only.
local FUNCTION_OR_BOOLEAN_FIELDS = { "cond", "enabled" }
local BOOLEAN_FIELDS = { "lazy", "submodules" }

--- Shallow copy of the ipairs part: compile must neither mutate nor share input tables.
local function copy_array(v)
	local result = {}
	for _, item in ipairs(v) do
		table.insert(result, item)
	end
	return result
end

--- Whether `value` occurs in a small array (all call sites are per-spec lists, so the linear scan is fine).
local function contains(list, value)
	for i = 1, #list do
		if list[i] == value then
			return true
		end
	end
	return false
end

local function normalize_array(v)
	if v == nil then
		return {}
	elseif type(v) == "string" then
		return { v }
	elseif type(v) == "table" then
		return copy_array(v)
	end
	return {}
end

--- Final run of non-"/"/":" bytes (equivalent to `s:match("([^/:]+)$")`, pinned by tests over adversarial inputs). Byte
--- loop because LuaJIT patterns run interpreted (~7 us/call, which dominated per-spec compile).
---@param s string
---@return string?
local function last_segment(s)
	local n = #s
	if n == 0 or s:byte(n) == 47 or s:byte(n) == 58 then -- "/" or ":"
		return nil
	end
	local i = n
	while i > 1 do
		local b = s:byte(i - 1)
		if b == 47 or b == 58 then -- "/" or ":"
			break
		end
		i = i - 1
	end
	return s:sub(i, n)
end

---@param src string
---@return string
local function strip_src_suffix(src)
	-- lazy.nvim and vim.pack both strip a trailing "/" then a trailing ".git" before taking the last path segment.
	local name = src
	if name:sub(-1) == "/" then
		name = name:sub(1, -2)
	end
	if name:sub(-4) == ".git" then
		name = name:sub(1, -5)
	end
	return name
end

---@param src string
---@return string
local function derive_name(src)
	-- lazy.nvim's Spec.get_name: strip .git, one trailing slash, then take the last segment; then drop a .nvim/.lua
	-- suffix. The suffix handling is why "user/repo.git" does not keep ".git" as the id.
	local name = strip_src_suffix(src)
	name = last_segment(name) or name
	if name:sub(-5) == ".nvim" then
		name = name:sub(1, -6)
	end
	if name:sub(-4) == ".lua" then
		name = name:sub(1, -5)
	end
	return name
end

-- vim.pack's own directory-name derivation: last segment, `.git` stripped. The install dir is `pack/<pkg>/opt/<name>`,
-- so this must match vim.pack or existing installs get re-cloned under a new name. A trailing slash resolves like
-- lazy.nvim here (vim.pack would yield an empty name).
local function pkg_name(src, spec_name)
	if spec_name then
		return spec_name
	end
	local name = strip_src_suffix(src)
	return last_segment(name) or name
end

--- Expand a leading "~". Byte test, not `:match("^~")`: LuaJIT patterns run
--- interpreted (~50 ns vs sub-ns on this hot path).
---@param path string
---@return string
local function expand_home(path)
	if path:byte(1) == 126 then -- "~"
		return vim.fn.expand(path)
	end
	return path
end

local function resolve_src(src, dir, url)
	if dir then
		return expand_home(dir)
	end

	if url then
		return url
	end

	if src then
		local b1 = src:byte(1)
		if b1 == 126 then -- "~"
			return vim.fn.expand(src)
		elseif b1 == 47 or b1 == 46 then -- "/" or "."
			return src
		elseif src:sub(1, 8) == "https://" or src:sub(1, 7) == "http://" or src:sub(1, 4) == "git@" then
			return src
		end
		return "https://github.com/" .. src
	end

	error("resolve_src: no source available (specify [1], .dir, or .url)", 0)
end

local function normalize_keys(v)
	if v == nil then
		return {}
	elseif type(v) == "string" then
		return { { lhs = v, mode = "n" } }
	elseif type(v) == "table" then
		local result = {}
		for _, item in ipairs(v) do
			if type(item) == "string" then
				table.insert(result, { lhs = item, mode = "n" })
			elseif type(item) == "table" then
				-- rhs: string (feedkeys), function, or false (lazy.nvim:
				-- disable the mapping, never load). Must not be
				-- `item.rhs or item[2]`: that swallows a false rhs and turns
				-- the key into a load trigger.
				local rhs = item.rhs
				if rhs == nil then
					rhs = item[2]
				end
				-- vim.NIL (JSON null / empty value) behaves like false.
				if rhs ~= nil and vim.NIL ~= nil and rhs == vim.NIL then
					rhs = false
				end
				table.insert(result, {
					lhs = item.lhs or item[1],
					mode = item.mode or "n",
					rhs = rhs,
					desc = item.desc,
					silent = item.silent,
					-- ft scopes the trigger to a buffer-local FileType map.
					ft = item.ft,
				})
			end
		end
		return result
	end
	return {}
end

--- Neovim stores some event names under a canonical alias (BufRead shows as BufReadPost). The dispatcher looks routes
--- up by ev.event, so normalize once here. Verified by creating rows and reading them back; matches lazy.nvim passing
--- names straight to nvim_create_autocmd.
local EVENT_ALIASES = {
	BufRead = "BufReadPost",
	BufCreate = "BufAdd",
	BufWrite = "BufWritePre",
}

--- Respect lazy.nvim's `{ event = ..., pattern = ... }` table as a one-item list: ipairs over a map-shaped table yields
--- nothing, which would silently make a lazy spec eager.
---@param v any
---@return {event: string, pattern?: string}[]
local function normalize_events(v)
	if v == nil then
		return {}
	end
	if type(v) == "string" then
		return { { event = EVENT_ALIASES[v] or v } }
	end
	if type(v) == "table" then
		local result = {}
		local items = v.event ~= nil and { v } or v
		for _, item in ipairs(items) do
			if type(item) == "string" then
				table.insert(result, { event = EVENT_ALIASES[item] or item })
			elseif type(item) == "table" then
				local events = type(item.event) == "table" and item.event or { item.event }
				for _, ev in ipairs(events) do
					table.insert(result, { event = EVENT_ALIASES[ev] or ev, pattern = item.pattern })
				end
			end
		end
		return result
	end
	return {}
end

--- Lower a lazy.nvim version spec to a vim.pack value: `version` becomes a semver range, refs become strings.
---@param spec LazeSpec
---@param idx? integer
---@param range? vim.VersionRange Already validated by validate_spec
---@return string|vim.VersionRange|nil
local function resolve_version(spec, idx, range)
	-- lazy.nvim precedence: commit > tag > version > branch.
	if spec.commit ~= nil then
		return spec.commit
	end
	if spec.tag ~= nil then
		return spec.tag
	end
	local v = spec.version
	if v ~= nil and v ~= false then
		-- Reuse the range validated during compile instead of parsing twice.
		return range or require("laze.semver").to_semver_range(v, idx)
	end
	-- false/omitted version: branch still applies, else vim.pack's default.
	return spec.branch
end

local function add_to_route(route_map, keys, plugin_id)
	for i = 1, #keys do
		local key = keys[i]
		if not route_map[key] then
			route_map[key] = {}
		end
		table.insert(route_map[key], plugin_id)
	end
end

--- One variant per (event, pattern): a patternless spec must not inherit
--- another spec's pattern, and a patterned spec must not fire unconditionally.
local function add_to_event_route(route_map, events, plugin_id)
	for i = 1, #events do
		local ev = events[i]
		local variants = route_map[ev.event]
		if not variants then
			variants = {}
			route_map[ev.event] = variants
		end
		local variant
		for j = 1, #variants do
			if variants[j].pattern == ev.pattern then
				variant = variants[j]
				break
			end
		end
		if not variant then
			variant = { pattern = ev.pattern, ids = {} }
			table.insert(variants, variant)
		end
		table.insert(variant.ids, plugin_id)
	end
end

--- Variant identity for `ft`: an ft set as one comparable string ("" = global).
local function ft_id(value)
	return value and table.concat(value, "\0") or ""
end

--- One variant per (lhs, mode); a `mode` array expands in declaration order. Each variant is an independent trigger
--- map, so an n-mode press cannot fire a v-only declaration. Variants sharing lhs+mode share one map, so mismatched
--- rhs/desc/silent warns and keeps the first.
local function add_to_key_route(route_map, keys, plugin_id)
	for i = 1, #keys do
		local ke = keys[i]
		local lhs = ke.lhs
		local modes = type(ke.mode) == "table" and ke.mode or { ke.mode }
		local seen_modes = {}
		for j = 1, #modes do
			local mode = modes[j]
			-- Dedup repeated modes. An empty mode array creates no variants (lazy.nvim resolves no handler and keeps the
			-- plugin lazy), so do not leave an empty route behind.
			if not seen_modes[mode] then
				seen_modes[mode] = true
				-- `ft` is part of lazy.nvim's handler id, so a buffer-local
				-- and a global declaration for the same lhs/mode are distinct.
				local ft = ke.ft
				if type(ft) == "string" then
					ft = { ft }
				elseif type(ft) == "table" then
					ft = copy_array(ft)
				end
				local variants = route_map[lhs]
				-- `rhs = false` / vim.NIL removes this plugin's id from
				-- lazy.nvim's resolved handler map. Declaration order matters:
				-- a later false cancels an earlier binding, a later binding
				-- re-adds. A shared variant only loses this plugin's id.
				if ke.rhs == false then
					if variants then
						local want = ft_id(ft)
						for k = #variants, 1, -1 do
							local variant = variants[k]
							if variant.mode == mode and ft_id(variant.ft) == want then
								for n = #variant.ids, 1, -1 do
									if variant.ids[n] == plugin_id then
										table.remove(variant.ids, n)
									end
								end
								if #variant.ids == 0 then
									table.remove(variants, k)
								end
							end
						end
						if #variants == 0 then
							route_map[lhs] = nil
						end
					end
				else
					if not variants then
						variants = {}
						route_map[lhs] = variants
					end
					local variant
					for k = 1, #variants do
						if variants[k].mode == mode and ft_id(variants[k].ft) == ft_id(ft) then
							variant = variants[k]
							break
						end
					end
					if not variant then
						variant = { mode = mode, ids = {}, rhs = ke.rhs, desc = ke.desc, silent = ke.silent, ft = ft }
						table.insert(variants, variant)
					elseif variant.rhs ~= ke.rhs or variant.desc ~= ke.desc or variant.silent ~= ke.silent then
						require("laze.diag").warn(
							("keys %q in mode %q is shared by multiple plugins with different rhs/opts — keeping the first"):format(
								lhs,
								mode
							)
						)
					end
					-- A plugin may declare the same (lhs, mode) more than once;
					-- its id still appears once (it is loaded at most once).
					if not contains(variant.ids, plugin_id) then
						table.insert(variant.ids, plugin_id)
					end
				end
			end
		end
	end
end

local CONSUMED_KEYS = {
	src = true,
	name = true,
	event = true,
	ft = true,
	cmd = true,
	keys = true,
	dev = true,
	dev_path = true,
	dir = true,
	url = true,
	init = true,
	config = true,
	cond = true,
	enabled = true,
	after = true,
	version = true,
	data = true,
	silent = true,
	dependencies = true,
	module = true,
	build = true,
	-- lazy.nvim fields mapped to vim.pack equivalents
	branch = true,
	tag = true,
	commit = true,
	-- pin is NOT consumed: vim.pack.Spec has `pin` (exclude from updates),
	-- so it flows through the unknown-field passthrough into the pack entry.
	-- lazy.nvim fields with no vim.pack equivalent (safely ignored, see warn_unsupported)
	priority = true,
	main = true,
	submodules = true,
	optional = true,
	specs = true,
	lazy = true,
	opts = true,
	import = true,
}

--- Accepted but without a vim.pack equivalent: consumed, never passed
--- through, warned once per field per compile (a notify costs ~180 us).
local UNSUPPORTED_FIELDS = {
	submodules = "vim.pack always fetches submodules; `submodules = false` cannot be honored",
	optional = "deps are always required; remove 'optional'",
	import = "lazy.nvim-only; load spec files yourself and pass the tables to setup",
	specs = "no equivalent; inline your specs instead",
}

local KEY_OPTION_FIELDS = {
	lhs = true,
	rhs = true,
	mode = true,
	desc = true,
	silent = true,
	ft = true,
}

--- Options accepted by a keys entry but dropped by laze (KD-016). Returns
--- the sorted option names shared with the route, or nil.
local function dropped_key_options(keys)
	local dropped
	if type(keys) ~= "table" then
		return nil
	end
	for _, item in ipairs(keys) do
		if type(item) == "table" then
			for field in pairs(item) do
				if type(field) == "string" and not KEY_OPTION_FIELDS[field] then
					dropped = dropped or {}
					dropped[field] = true
				end
			end
		end
	end
	if not dropped then
		return nil
	end
	local names = {}
	for field in pairs(dropped) do
		table.insert(names, field)
	end
	table.sort(names)
	return names
end

local function warn_unsupported(spec, idx, spec_id, warned, notify)
	for field, reason in pairs(UNSUPPORTED_FIELDS) do
		-- `submodules = true` (and the default) already matches vim.pack; only the opt-out is a real difference.
		local differs = field ~= "submodules" or spec.submodules == false
		if spec[field] ~= nil and differs and not warned[field] then
			warned[field] = true
			notify(
				"KD-020",
				("spec [%d] (%s): '%s' is not supported by laze (%s)"):format(idx, spec_id, field, reason),
				"KD-020:" .. field
			)
		end
	end
end

local function is_string_array(v)
	if type(v) ~= "table" then
		return false
	end
	for _, item in ipairs(v) do
		if type(item) ~= "string" then
			return false
		end
	end
	return true
end

--- Function-shaped triggers are valid in lazy.nvim but rejected here: laze has no runtime evaluation, and normalizing
--- them to "no trigger" would silently make the plugin eager.
local function validate_triggers(spec, idx, spec_id)
	local function bad(field, msg)
		require("laze.diag").bad(idx, spec_id, field, msg)
	end

	for _, field in ipairs(TRIGGER_FIELDS) do
		local value = spec[field]
		if type(value) == "function" then
			bad(field, "must be a string or array — function triggers are not supported by laze")
		elseif value ~= nil and type(value) ~= "string" and type(value) ~= "table" then
			bad(field, "must be a string or array")
		elseif value == "" then
			-- Would match everything (FileType "") or raise at plan time.
			bad(field, "must not be empty")
		end
	end

	if type(spec.event) == "table" then
		local function check_event_spec(item, label)
			local ev = item.event
			if type(ev) == "string" then
				if ev == "" then
					bad(label, "event must not be empty")
				end
			elseif not is_string_array(ev) then
				bad(label, "must have event = string | string[]")
			else
				for _, e in ipairs(ev) do
					if e == "" then
						bad(label, "event must not be empty")
					end
				end
			end
			if item.pattern ~= nil and type(item.pattern) ~= "string" then
				bad(label, "pattern must be a string")
			end
		end

		-- Single `{ event = ..., pattern = ... }` table or the array form.
		if spec.event.event ~= nil then
			check_event_spec(spec.event, "event")
		else
			for i, item in ipairs(spec.event) do
				local label = "event[" .. i .. "]"
				if type(item) == "table" then
					check_event_spec(item, label)
				elseif type(item) ~= "string" then
					bad(label, "must be a string or { event, pattern } table")
				elseif item == "" then
					bad(label, "must not be empty")
				end
			end
		end
	end

	for _, field in ipairs(ARRAY_TRIGGER_FIELDS) do
		local value = spec[field]
		if type(value) == "table" then
			for i, item in ipairs(value) do
				if type(item) ~= "string" then
					bad(field .. "[" .. i .. "]", "must be a string")
				elseif item == "" then
					bad(field .. "[" .. i .. "]", "must not be empty")
				end
			end
		end
	end

	if type(spec.keys) == "table" then
		for i, item in ipairs(spec.keys) do
			if type(item) == "table" then
				local lhs = item.lhs or item[1]
				if type(lhs) ~= "string" or lhs == "" then
					bad("keys[" .. i .. "]", "must have a non-empty lhs (string)")
				end
				-- rhs is string|fun|false (plus vim.NIL from JSON null). Anything else would fail later inside
				-- nvim_replace_termcodes; reject it now.
				local rhs = item.rhs
				if rhs == nil then
					rhs = item[2]
				end
				local is_nil = rhs ~= nil and vim.NIL ~= nil and rhs == vim.NIL
				if rhs ~= nil and not is_nil and rhs ~= false and type(rhs) ~= "string" and type(rhs) ~= "function" then
					bad("keys[" .. i .. "].rhs", "must be a string, function, false, or vim.NIL")
				end
				if item.ft ~= nil then
					-- FileType autocmd pattern for the buffer-local map.
					if type(item.ft) == "string" then
						if item.ft == "" then
							bad("keys[" .. i .. "].ft", "must not be empty")
						end
					elseif not is_string_array(item.ft) then
						bad("keys[" .. i .. "].ft", "must be a string or string[]")
					else
						for _, ft in ipairs(item.ft) do
							if ft == "" then
								bad("keys[" .. i .. "].ft", "must not contain empty filetypes")
							end
						end
					end
				end
				-- lazy.nvim does not validate mode contents: "" makes a multi-mode mapping and {} yields no handler while the
				-- plugin stays lazy. Match it instead of rejecting.
				if item.mode ~= nil and type(item.mode) ~= "string" and not is_string_array(item.mode) then
					bad("keys[" .. i .. "]", "mode must be a string or string[]")
				end
			elseif type(item) ~= "string" then
				bad("keys[" .. i .. "]", "must be a string or an entry table")
			elseif item == "" then
				bad("keys[" .. i .. "]", "must not be empty")
			end
		end
	end
end

---@param spec LazeSpec
---@return boolean
local function has_dev_source(spec)
	return spec.dev == true
		or (type(spec.dev) == "string" and spec.dev ~= "")
		or (type(spec.dev_path) == "string" and spec.dev_path ~= "")
end

--- lazy.nvim `dev.patterns`: plain substring match against the plugin URL.
---@param patterns string[]
---@param url string
---@return boolean
local function matches_dev_pattern(patterns, url)
	for i = 1, #patterns do
		if url:find(patterns[i], 1, true) then
			return true
		end
	end
	return false
end

--- Plain-Lua unit runs may have no `vim.fn`; there, keep the dev source.
---@param path string
---@return boolean
local function is_directory(path)
	if type(vim.fn.isdirectory) ~= "function" then
		return true
	end
	return vim.fn.isdirectory(path) == 1
end

---@param spec LazeSpec
---@param idx integer
---@param warned table<string, boolean>
---@param notify fun(id: string, detail: string)
---@return vim.VersionRange|nil
local function validate_spec(spec, idx, warned, notify)
	local src = spec[1] or spec.src
	if not src and not spec.dir and not spec.url then
		require("laze.diag").spec_at(idx, "missing source — use [1], .src, .dir, or .url")
	end
	if src ~= nil and (type(src) ~= "string" or src == "") then
		require("laze.diag").spec_at(idx, "[1]/src must be a non-empty string")
	end
	for _, f in ipairs(SOURCE_FIELDS) do
		local value = spec[f]
		if value ~= nil and (type(value) ~= "string" or value == "") then
			require("laze.diag").spec_at(idx, f .. " must be a non-empty string")
		end
	end

	local spec_id = tostring(src or spec.dir or spec.url)

	-- One short call per check; `require("laze.diag")` stays inline so it is parsed only when a message actually fires.
	local function err(msg)
		require("laze.diag").spec(idx, spec_id, msg)
	end

	warn_unsupported(spec, idx, spec_id, warned, notify)

	local dropped = dropped_key_options(spec.keys)
	if dropped then
		notify(
			"KD-016",
			("spec [%d] (%s): keys option(s) %s are dropped"):format(idx, spec_id, table.concat(dropped, ", "))
		)
	end

	if spec.dev == "" then
		require("laze.diag").warn(("spec [%d] (%s) has dev='' — ignored"):format(idx, spec_id))
	end

	if spec.init ~= nil and type(spec.init) ~= "function" then
		err("init must be a function")
	end
	if spec.config ~= nil and type(spec.config) ~= "function" and spec.config ~= true then
		-- The table form is lazy.nvim's removed opts alias, so name the
		-- replacements instead of giving the generic type error.
		if type(spec.config) == "table" then
			err(
				'config = { ... } (lazy.nvim\'s deprecated opts alias) is not supported — use main = "..." with opts = {...}, or config = function() ... end'
			)
		else
			err("config must be a function or true")
		end
	end
	-- `opts` desugars to require(main).setup(opts) at load; main is resolved
	-- then because the plugin is not installed at compile time.
	if spec.opts ~= nil and type(spec.opts) ~= "table" and type(spec.opts) ~= "function" then
		err("opts must be a table or function")
	end
	if spec.main ~= nil and (type(spec.main) ~= "string" or spec.main == "") then
		err("main must be a non-empty string")
	end
	for _, field in ipairs(FUNCTION_OR_BOOLEAN_FIELDS) do
		local value = spec[field]
		if value ~= nil and type(value) ~= "function" and type(value) ~= "boolean" then
			err(field .. " must be a function or boolean")
		end
	end
	for _, field in ipairs(BOOLEAN_FIELDS) do
		local value = spec[field]
		if value ~= nil and type(value) ~= "boolean" then
			err(field .. " must be a boolean")
		end
	end
	if spec.after ~= nil then
		if type(spec.after) ~= "table" then
			err("after must be an array of plugin ids")
		end
		for i, dep_id in ipairs(spec.after) do
			if type(dep_id) ~= "string" or dep_id == "" then
				err("after[" .. i .. "] must be a non-empty plugin id string")
			end
		end
	end
	local dependencies = spec.dependencies
	if dependencies ~= nil then
		if type(dependencies) ~= "string" and type(dependencies) ~= "table" then
			err("dependencies must be a string, name array, or spec array")
		elseif type(dependencies) == "table" then
			for i, dep in ipairs(dependencies) do
				if type(dep) ~= "string" and type(dep) ~= "table" then
					err("dependencies[" .. i .. "] must be a string or spec table")
				end
			end
		end
	end
	local build = spec.build
	if build ~= nil and type(build) ~= "string" and type(build) ~= "function" and build ~= false then
		if type(build) == "table" then
			for i, item in ipairs(build) do
				if type(item) ~= "string" and type(item) ~= "function" then
					err("build[" .. i .. "] must be a string or function")
				end
			end
		else
			err("build must be a string, function, false, or a list of strings/functions")
		end
	end
	local module = spec.module
	if module ~= nil and type(module) ~= "string" and type(module) ~= "table" and module ~= false then
		err("module must be a string, array, or false")
	end
	if type(module) == "table" then
		if #module == 0 then
			err("module must not be an empty array — use false or omit it")
		end
		for i, mod in ipairs(module) do
			if type(mod) ~= "string" or mod == "" then
				err("module[" .. i .. "] must be a non-empty string")
			end
		end
	end
	if spec.priority ~= nil and type(spec.priority) ~= "number" then
		err("priority must be a number")
	end
	local version_range
	local version = spec.version
	if version ~= nil and version ~= false then
		if type(version) ~= "string" then
			err("version must be a string (semver range) or false")
		end
		-- lazy.nvim precedence is commit > tag > version > branch, so only parse a range that can win. The returned object
		-- is reused by resolve_version. semver is required lazily: most configs never use it. Local checkouts (`dir`, an
		-- active dev source) ignore version/refs (KD-004), so their ranges are validated but never lowered.
		if spec.commit == nil and spec.tag == nil and spec.dir == nil and not has_dev_source(spec) then
			version_range = require("laze.semver").to_semver_range(version, idx, spec_id)
		end
	end
	for _, f in ipairs(VERSION_REF_FIELDS) do
		local value = spec[f]
		if value ~= nil and (type(value) ~= "string" or value == "") then
			err(f .. " must be a non-empty string")
		end
	end

	validate_triggers(spec, idx, spec_id)
	return version_range
end

-- lazy.nvim's Util.is_list: keys exactly 1..n; empty tables count. This is what makes `{ { "foo/bar" } }` a nested spec
-- list rather than a spec with a table source.
local function is_list(t)
	local i = 0
	for _ in pairs(t) do
		i = i + 1
		if t[i] == nil then
			return false
		end
	end
	return true
end

--- Flatten lazy.nvim-shaped spec lists: a bare source string is `{ src }`, and lists may nest. Spec tables are kept by
--- reference. Mirrors lazy.nvim's Spec:normalize so a working config does not crash here.
---@param spec any
---@param out LazeSpec[]
---@param label string
local function flatten_spec(spec, out, label)
	if type(spec) == "string" then
		table.insert(out, { spec })
		return
	end
	if type(spec) ~= "table" then
		error("compile: " .. label .. " must be a spec table or string", 0)
	end

	if is_list(spec) then
		for i = 1, #spec do
			flatten_spec(spec[i], out, label .. "[" .. i .. "]")
		end
		return
	end
	-- More entries than a dense 1..n layout but not a list: sparse.
	if #spec > 1 then
		error("compile: " .. label .. " must not be sparse", 0)
	end

	-- Sparse numeric lists (e.g. { [1] = "foo", [3] = "bar" }) would silently
	-- drop trailing entries under ipairs; reject them.
	local numeric, string = false, false
	for k in pairs(spec) do
		if type(k) == "number" then
			numeric = true
		elseif type(k) == "string" then
			string = true
		end
	end
	if numeric and not string then
		error("compile: " .. label .. " must not be sparse", 0)
	end

	if spec[1] ~= nil or spec.src ~= nil or spec.dir ~= nil or spec.url ~= nil then
		table.insert(out, spec)
		return
	end

	error("compile: " .. label .. " must be a spec table or string", 0)
end

---@param specs LazeSpec[]|string|LazeSpec
---@param opts? { dev_root?: string, dev?: { path?: string, patterns?: string[] } }
---@return LazeCompiled
local function compile(specs, opts)
	if specs == nil then
		error("compile: expected a non-empty array of specs", 0)
	end
	local flattened = {}
	flatten_spec(specs, flattened, "specs")
	if #flattened == 0 then
		error("compile: expected a non-empty array of specs", 0)
	end
	specs = flattened

	local dev_opts = opts and opts.dev
	if dev_opts ~= nil and type(dev_opts) ~= "table" then
		error("compile: opts.dev must be a table", 0)
	end
	if dev_opts and dev_opts.path ~= nil and type(dev_opts.path) ~= "string" then
		error("compile: opts.dev.path must be a string", 0)
	end
	if dev_opts and dev_opts.fallback ~= nil and type(dev_opts.fallback) ~= "boolean" then
		error("compile: opts.dev.fallback must be a boolean", 0)
	end
	local dev_root = (dev_opts and dev_opts.path) or (opts and opts.dev_root) or "~/projects"
	local dev_fallback = dev_opts and dev_opts.fallback == true
	-- Plain substrings against the plugin URL (not Lua patterns), applied only when the spec does not set `dev`. Copy so
	-- later opts mutation cannot change a compile.
	local dev_patterns = {}
	if dev_opts and dev_opts.patterns ~= nil then
		if type(dev_opts.patterns) ~= "table" then
			error("compile: opts.dev.patterns must be an array of strings", 0)
		end
		for i, pattern in ipairs(dev_opts.patterns) do
			if type(pattern) ~= "string" or pattern == "" then
				error(("compile: opts.dev.patterns[%d] must be a non-empty string"):format(i), 0)
			end
			dev_patterns[i] = pattern
		end
	end

	-- Index top-level names and resolved sources first, so dependency expansion can reference user-defined specs instead
	-- of re-registering them. This is what keeps `{ "foo/baz", name = "bar" }` from being duplicated as `baz` when
	-- another spec depends on `"foo/baz"`.
	local spec_names = {}
	local spec_srcs = {}
	for _, spec in ipairs(specs) do
		local base = spec[1] or spec.src or spec.dir or spec.url
		local name = spec.name or (base and derive_name(base))
		if name then
			spec_names[name] = true
		end
		if base then
			local ok, resolved = pcall(resolve_src, spec[1] or spec.src, spec.dir, spec.url)
			if ok and resolved and name then
				spec_srcs[resolved] = name
			end
		end
	end

	local expanded = {}
	local expanded_names = {}
	local expanded_srcs = {}
	-- Known-difference messages are deduped per compile (issue #12); the
	-- closure is shared by dependency expansion and spec validation.
	local kd_notified = {}
	local function notify_kd(id, detail, key)
		-- Rare path: keep the require off startup.
		require("laze.known_differences").notify(id, detail, kd_notified, opts, key)
	end
	-- Dependency-derived `after` names live here, not on the user's spec tables: compile must stay a pure transform (the
	-- same table may be passed to lazy.nvim afterwards).
	local dep_after = {}

	--- Expand one spec's dependencies recursively, deepest first, so `after` always points at a registered id. Top-level
	--- names are referenced, not re-registered (lazy.nvim's fragment merge is out of scope).
	---@param spec table
	---@param label string
	local function expand_dependencies(spec, label)
		-- lazy.nvim skips deps of a plugin disabled at compile time. Function-valued cond/enabled cannot be decided here,
		-- so expand and let the plan skip the parent.
		if spec.dependencies == nil or spec.enabled == false or spec.cond == false then
			return
		end
		-- Guard shapes before derive/expand: validate_spec runs later and a
		-- malformed value would crash with a raw index error here.
		if type(spec.dependencies) ~= "string" and type(spec.dependencies) ~= "table" then
			error(label .. ": dependencies must be a string, name array, or spec array", 0)
		end
		local deps = type(spec.dependencies) == "table" and spec.dependencies or { spec.dependencies }
		local dep_names = {}
		for i, dep in ipairs(deps) do
			if type(dep) ~= "string" and type(dep) ~= "table" then
				error(label .. ": dependencies[" .. i .. "] must be a string or spec table", 0)
			end
			local dep_spec = type(dep) == "string" and { dep } or dep
			-- Same derivation as the compile loop, so dir/url-only inline deps resolve to the id the registry will use.
			local dep_base = dep_spec[1] or dep_spec.src or dep_spec.dir or dep_spec.url
			local dep_name = dep_spec.name or derive_name(dep_base or "")
			local dep_src
			if dep_base then
				local ok, resolved = pcall(resolve_src, dep_spec[1] or dep_spec.src, dep_spec.dir, dep_spec.url)
				if ok then
					dep_src = resolved
				end
			end
			-- Prefer a top-level spec by name, then by resolved source (a renamed spec must not be re-registered under its
			-- repo name), then an already-expanded dep.
			local existing_top = (spec_names[dep_name] and dep_name) or (dep_src and spec_srcs[dep_src])
			local existing_expanded = (dep_src and expanded_srcs[dep_src]) or (expanded_names[dep_name] and dep_name)
			local target = existing_top or existing_expanded or dep_name
			-- Same dep listed twice (including aliases for one plugin) wires once.
			if not contains(dep_names, target) then
				table.insert(dep_names, target)
				if not existing_top and not existing_expanded then
					-- Mark before recursing so a cycle references the in-flight spec instead of recursing forever.
					expanded_names[dep_name] = true
					if dep_src then
						expanded_srcs[dep_src] = dep_name
					end
					expand_dependencies(dep_spec, ("dependency %q"):format(dep_name))
					table.insert(expanded, dep_spec)
				end
			end
		end
		dep_after[spec] = dep_names
	end

	for idx, spec in ipairs(specs) do
		expand_dependencies(spec, "spec [" .. idx .. "]")
		table.insert(expanded, spec)
	end

	local pack = {}
	local registry = {}
	local routes = {
		events = {},
		fts = {},
		cmds = {},
		keys = {},
		modules = {},
	}

	-- Deduped per field per compile: one vim.notify costs ~180 us headless, so N specs sharing a field must not pay N
	-- times. The first offending spec is named in the message.
	local warned = {}

	for idx, spec in ipairs(expanded) do
		local version_range = validate_spec(spec, idx, warned, notify_kd)

		local src = spec[1] or spec.src
		local dir = spec.dir
		local url = spec.url
		local base_src = src or dir or url
		local name = spec.name or derive_name(base_src)
		-- Directory name under pack/<pkg>/opt/: vim.pack's derivation unless the user pinned `name`.
		local pkg = pkg_name(base_src or name, spec.name)

		if registry[name] then
			-- Same id twice would drop the first spec's init/config/after but
			-- keep its pack entry and trigger ids; refuse instead.
			error(
				"spec ["
					.. idx
					.. "] ("
					.. tostring(src or dir or url)
					.. ") has duplicate name '"
					.. name
					.. "' (already defined by "
					.. tostring(registry[name].src)
					.. ")",
				0
			)
		end
		local enabled = spec.enabled
		if enabled == nil then
			enabled = true
		end

		-- Merge explicit `after` with dependency-derived names in that order, without touching the user's spec table. Dedup
		-- keeps a dep named both ways wired once.
		local after = dep_after[spec] or {}
		if spec.after then
			local merged = copy_array(spec.after)
			for _, n in ipairs(after) do
				if not contains(merged, n) then
					table.insert(merged, n)
				end
			end
			after = merged
		end

		-- build = false means "no build". Must not be `spec.build == false and nil or spec.build`: nil cannot flow through
		-- and/or, so that returns false again.
		local build = spec.build
		if build == false or (type(build) == "table" and #build == 0) then
			build = nil
		end

		-- opts without config, and config = true, desugar to require(main).setup(opts) at load. main is resolved at load
		-- time because the plugin is not installed during compile. The closure captures only pure values, so recompiles are
		-- deterministic.
		local config = spec.config
		if config == nil and spec.opts ~= nil then
			config = true
		end
		if config == true then
			local explicit_main = spec.main
			local plugin_name = name
			config = function(plugin, config_opts)
				local main = explicit_main or require("laze.mainmod").get_main(plugin and plugin.dir, plugin_name)
				if not main then
					error(
						("Lua module not found for config of %s. Please use a `config()` function instead"):format(plugin_name),
						0
					)
				end
				local mod = require(main)
				if type(mod.setup) ~= "function" then
					error(("module %q has no setup function"):format(main), 0)
				end
				mod.setup(config_opts or {})
			end
		end

		local norm = {
			src = src,
			name = name,
			event = normalize_events(spec.event),
			ft = normalize_array(spec.ft),
			cmd = normalize_array(spec.cmd),
			keys = normalize_keys(spec.keys),
			dev = spec.dev,
			dir = dir,
			url = url,
			init = spec.init,
			config = config,
			cond = spec.cond,
			enabled = enabled,
			after = after,
			build = build,
			module = spec.module,
			main = spec.main,
			opts = spec.opts,
			dev_path = spec.dev_path,
		}

		local resolved_src = resolve_src(norm.src, norm.dir, norm.url)

		-- Module name(s) that trigger on require(). Explicit only: repo names
		-- do not reliably match module names (cmp-buffer ships cmp_buffer).
		local modname = norm.module

		-- Resolved once here. A non-nil dev_src also marks a local checkout, which changes version handling below.
		local dev_src
		local dev_from_root = false
		if norm.dev == true then
			dev_from_root = true
			dev_src = vim.fn.expand(dev_root .. "/" .. name)
		elseif type(norm.dev) == "string" and norm.dev ~= "" then
			-- Per-plugin dev directory: ~ expands, absolute/relative stay verbatim.
			dev_src = expand_home(norm.dev)
		elseif norm.dev_path then
			dev_src = expand_home(norm.dev_path)
		elseif norm.dev == nil and norm.dir == nil and matches_dev_pattern(dev_patterns, resolved_src) then
			-- A URL substring match acts like `dev = true` (`<dev_root>/<name>`) when the spec neither opts in nor out.
			dev_from_root = true
			dev_src = vim.fn.expand(dev_root .. "/" .. name)
		end
		-- `dev.fallback`: a missing root-derived clone falls back to the remote
		-- source. Explicit `dev = "<path>"` / `dev_path` are never probed.
		if dev_src and dev_from_root and dev_fallback and not is_directory(dev_src) then
			dev_src = nil
		end
		local final_src = dev_src or resolved_src

		-- `dir` plugins are local: vim.pack must not install them (it would
		-- git-clone the path). The plan loads them by exact rtp path.
		local is_local = norm.dir ~= nil

		registry[name] = {
			id = name,
			src = final_src,
			dir = is_local and final_src or nil,
			init = norm.init,
			config = norm.config,
			cond = norm.cond,
			enabled = norm.enabled,
			after = norm.after,
			silent = spec.silent == true,
			build = norm.build,
			module = modname,
			main = norm.main,
			opts = norm.opts,
			priority = type(spec.priority) == "number" and spec.priority or 50,
			dev = norm.dev,
			dev_path = norm.dev_path,
			lazy = spec.lazy,
			has_route = false, -- set below
			-- Not `is_local and nil or pkg`: nil cannot flow through and/or. Local dir plugins have no pack entry.
			pkg = (not is_local) and pkg or nil,
		}

		if is_local then
			if norm.build ~= nil then
				require("laze.diag").warn(
					"plugin '" .. name .. "' is a local dir; build is not run (vim.pack does not install or rebuild local dirs)"
				)
			end
		else
			local pack_entry = {
				src = final_src,
				-- Must match vim.pack's own dir derivation (pkg_name) so existing installs keep working; the registry id may
				-- differ (id "which-key" vs dir "which-key.nvim") and must never be used for `:packadd`.
				name = pkg,
			}
			-- An active dev path is a local checkout: lowering version/branch/tag/commit would make vim.pack clone the dev
			-- path and check out that ref instead of loading the working tree. Same policy as `dir` (validate the range,
			-- never lower it).
			local resolved_version
			if dev_src == nil then
				resolved_version = resolve_version(spec, idx, version_range)
			end
			if resolved_version ~= nil then
				pack_entry.version = resolved_version
			end
			if spec.data ~= nil then
				pack_entry.data = spec.data
			end
			-- Use the normalized value (issue #50): `false` and `{}` both mean "no build" (lazy.nvim 306a055 iterates the
			-- builder list, so both run nothing), while nil leaves build-file discovery open. The raw `{}` leaked into the
			-- pack spec, where it is off-type for vim.pack.Spec and disagreed with the registry entry.
			if norm.build ~= nil then
				pack_entry.build = norm.build
			end
			-- Unknown fields pass through for forward compat.
			for key, value in pairs(spec) do
				if type(key) == "string" and not CONSUMED_KEYS[key] then
					pack_entry[key] = value
				end
			end
			table.insert(pack, pack_entry)
		end

		add_to_event_route(routes.events, norm.event, name)
		add_to_route(routes.fts, norm.ft, name)
		add_to_route(routes.cmds, norm.cmd, name)
		add_to_key_route(routes.keys, norm.keys, name)
		if norm.module then
			add_to_route(routes.modules, type(norm.module) == "table" and norm.module or { norm.module }, name)
		end
		registry[name].has_route = #norm.event > 0
			or #norm.ft > 0
			or #norm.cmd > 0
			or #norm.keys > 0
			or (norm.module ~= nil and norm.module ~= false)
	end

	for id, entry in pairs(registry) do
		for _, dep_id in ipairs(entry.after or {}) do
			if not registry[dep_id] then
				require("laze.diag").warn(
					"plugin '" .. id .. "' has after dependency on '" .. dep_id .. "' which does not exist"
				)
			end
		end
	end

	-- `after` deps are never eager: they load via their parents (eager parents at startup, lazy parents at trigger time).
	-- Shared by init.lua and plan.lua so both agree on "eager".
	local is_dep = {}
	for _, entry in pairs(registry) do
		for _, dep_id in ipairs(entry.after or {}) do
			is_dep[dep_id] = true
		end
	end
	for id, entry in pairs(registry) do
		entry.is_dep = is_dep[id] == true
		-- lazy.nvim's `lazy` override:
		--   false -> eager even with triggers / dep status
		--   true  -> never eager
		--   nil   -> eager only without triggers and not a dep
		entry.eager = entry.lazy == false or (entry.lazy ~= true and not entry.has_route and not entry.is_dep)
	end

	return {
		pack = pack,
		registry = registry,
		routes = routes,
	}
end

-- Exported for the standalone unit tests and extras.
return {
	compile = compile,
	derive_name = derive_name,
	pkg_name = pkg_name,
	resolve_src = resolve_src,
	normalize_keys = normalize_keys,
	normalize_events = normalize_events,
	resolve_version = resolve_version,
	CONSUMED_KEYS = CONSUMED_KEYS,
	UNSUPPORTED_FIELDS = UNSUPPORTED_FIELDS,
}
