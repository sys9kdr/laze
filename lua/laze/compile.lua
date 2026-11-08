local TRIGGER_FIELDS = { "event", "ft", "cmd", "keys" }
local ARRAY_TRIGGER_FIELDS = { "ft", "cmd" }
local SOURCE_FIELDS = { "dir", "url", "name" }
local VERSION_REF_FIELDS = { "branch", "tag", "commit" }

local function normalize_array(v)
	if v == nil then
		return {}
	end
	if type(v) == "string" then
		return { v }
	end
	if type(v) == "table" then
		local result = {}
		for _, item in ipairs(v) do
			table.insert(result, item)
		end
		return result
	end
	return {}
end

-- Byte codes for last_segment's backward scan ("/" and ":"). Byte loops
-- stay JIT-compiled; string.match/gsub are NYI and run interpreted
-- (~7 us/call, which dominated per-spec compile cost).
local SLASH_BYTE, COLON_BYTE = 47, 58

---Byte-scan equivalent of `s:match("([^/:]+)$")`: the final run of
---non-"/"/":" bytes anchored at the end of `s`. nil where the pattern
---would fail (empty input or trailing separator). Verified equivalent to
---the pattern form over 300k adversarial inputs (tests/test_compile.lua
---pins the edge cases).
---@param s string
---@return string?
local function last_segment(s)
	local n = #s
	if n == 0 or s:byte(n) == SLASH_BYTE or s:byte(n) == COLON_BYTE then
		return nil
	end
	local i = n
	while i > 1 do
		local b = s:byte(i - 1)
		if b == SLASH_BYTE or b == COLON_BYTE then
			break
		end
		i = i - 1
	end
	return s:sub(i, n)
end

---@param src string
---@return string
local function strip_src_suffix(src)
	-- Strip a trailing "/", then a trailing ".git": lazy.nvim and vim.pack
	-- both do exactly this before taking the last path segment.
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
	-- lazy.nvim-compatible (lazy/core/plugin.lua Spec.get_name): strip a
	-- trailing `.git`, then one trailing slash, then take the last path
	-- segment. Without the braces, "user/repo.git" keeps the .git suffix
	-- and "…/plugin/" (trailing slash) falls back to the raw URL as id.
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

-- vim.pack's own directory-name derivation (runtime/lua/vim/pack.lua):
-- the last path segment with a trailing `.git` stripped. The installed
-- directory is `pack/<pkg>/opt/<name>`, so this must match vim.pack
-- exactly — otherwise existing installs get re-cloned under a new name.
-- A trailing slash is tolerated (vim.pack yields an empty name for it
-- and would error; here it resolves like lazy.nvim does).
local function pkg_name(src, spec_name)
	if spec_name then
		return spec_name
	end
	local name = strip_src_suffix(src)
	return last_segment(name) or name
end

--- Expand a leading "~" via the API (one call per dev/dir spec; compile is
--- one-shot). Byte test, not `:match("^~")`: patterns are NYI in LuaJIT and
--- run interpreted (~50 ns vs sub-ns per call on this hot path).
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
		end
		if b1 == 47 or b1 == 46 then -- "/" or "."
			return src
		end
		if src:sub(1, 8) == "https://" or src:sub(1, 7) == "http://" or src:sub(1, 4) == "git@" then
			return src
		end
		return "https://github.com/" .. src
	end

	error("resolve_src: no source available (specify [1], .dir, or .url)", 0)
end

local function normalize_keys(v)
	if v == nil then
		return {}
	end
	if type(v) == "string" then
		return { { lhs = v, mode = "n" } }
	end
	if type(v) == "table" then
		local result = {}
		for _, item in ipairs(v) do
			if type(item) == "string" then
				table.insert(result, { lhs = item, mode = "n" })
			elseif type(item) == "table" then
				-- rhs: string (feedkeys), function (opaque callback), or
				-- `false` (lazy.nvim: disable the mapping, never load).
				-- NOT `item.rhs or item[2]`: a false rhs would be swallowed
				-- and the key would silently become a load trigger.
				local rhs = item.rhs
				if rhs == nil then
					rhs = item[2]
				end
				-- lazy.nvim's handler treats `vim.NIL` (a JSON null, or an
				-- empty keymap value) exactly like `false`: the entry is
				-- removed from the resolved handler map.
				if rhs ~= nil and vim.NIL ~= nil and rhs == vim.NIL then
					rhs = false
				end
				table.insert(result, {
					lhs = item.lhs or item[1],
					mode = item.mode or "n",
					rhs = rhs,
					-- lazy.nvim key options (passed to vim.keymap.set)
					desc = item.desc,
					silent = item.silent,
					-- ft scopes the trigger to a buffer-local mapping on
					-- matching FileType (lazy.nvim LazyKeysSpec.ft).
					ft = item.ft,
				})
			end
		end
		return result
	end
	return {}
end

--- Neovim stores some event names under a canonical alias
--- (`:autocmd BufRead` shows as `BufReadPost`). The grouped dispatcher
--- looks routes up by `ev.event`, so keys must use the stored form —
--- normalize here, once, instead of at every fire. Verified empirically
--- (create + read back rows): BufRead→BufReadPost, BufCreate→BufAdd,
--- BufWrite→BufWritePre. Matches lazy.nvim behavior (it passes names
--- straight to nvim_create_autocmd, which applies the same mapping).
local EVENT_ALIASES = {
	BufRead = "BufReadPost",
	BufCreate = "BufAdd",
	BufWrite = "BufWritePre",
}

--- Normalize lazy.nvim event values
--- (string | string[] | {event,pattern} | {event,pattern}[]).
---@param v any
---@return {event: string, pattern?: string}[] -- event name and optional pattern
local function normalize_events(v)
	if v == nil then
		return {}
	end
	if type(v) == "string" then
		return { { event = EVENT_ALIASES[v] or v } }
	end
	if type(v) == "table" then
		local result = {}
		-- lazy.nvim's LazyEventSpec is a string, a list, or a single
		-- { event = ..., pattern = ... } table. Treat the latter as a
		-- one-item list: ipairs over a map-shaped table yields nothing, so
		-- dropping it would silently turn a lazy spec eager.
		local items = v.event ~= nil and { v } or v
		for _, item in ipairs(items) do
			if type(item) == "string" then
				table.insert(result, { event = EVENT_ALIASES[item] or item })
			elseif type(item) == "table" then
				-- lazy.nvim form: { event = {"BufReadPre", "BufReadPost"}, pattern = "*.lua" }
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

--- Resolve lazy.nvim version spec to a vim.pack-compatible version value.
--- lazy.nvim: version = semver range string | false; branch/tag/commit are refs.
--- vim.pack:  version accepts a git ref string or a VersionRange.
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
		-- Field-based lowering: a version string is always a semver range,
		-- never a git ref (refs use branch/tag/commit). Reuse the range
		-- validated during compile instead of parsing the same string twice.
		return range or require("laze.semver").to_semver_range(v, idx)
	end
	-- version = false (or omitted) means "do not pin a range"; branch still
	-- applies, then vim.pack's default branch when neither is set.
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

--- Event routes carry optional autocmd patterns (lazy.nvim `{event, pattern}` form).
--- Each event name maps to a list of pattern variants: the same event with
--- DIFFERENT patterns routes independently (plan.lua creates one autocmd per
--- variant), while the same (event, pattern) pair shares one variant. Keying
--- by name alone would make a patternless spec inherit another spec's pattern
--- (and never load), or make a patterned spec fire unconditionally.
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

--- Key routes are per (lhs, mode) variant: `routes.keys[lhs]` is an array
--- with one entry per normalized mode (a `mode` array expands to one
--- variant per mode, in declaration order). Each variant is an independent
--- trigger map, so an n-mode press can never fire a v-only declaration and
--- vice versa. Variants sharing lhs+mode must agree on rhs/desc/silent:
--- the trigger map is shared, so warn and keep the first instead of
--- silently dropping the second spec's values.
local function add_to_key_route(route_map, keys, plugin_id)
	for i = 1, #keys do
		local ke = keys[i]
		local lhs = ke.lhs
		local modes = type(ke.mode) == "table" and ke.mode or { ke.mode }
		local seen_modes = {}
		for j = 1, #modes do
			local mode = modes[j]
			-- `mode = { "n", "n" }`: one variant, not two maps for one lhs.
			-- An empty mode array creates no variants at all (lazy.nvim
			-- resolves no key handler and keeps the plugin lazy); don't
			-- leave an empty `routes.keys[lhs]` entry behind.
			if not seen_modes[mode] then
				seen_modes[mode] = true
				-- `ft` is part of lazy.nvim's handler id (one id per
				-- lhs+mode+ft set), so a buffer-local declaration and a
				-- global one for the same lhs/mode are distinct variants.
				local ft = ke.ft
				if type(ft) == "string" then
					ft = { ft }
				elseif type(ft) == "table" then
					-- copy: compile must not mutate or share the input table
					local copy = {}
					for _, value in ipairs(ft) do
						table.insert(copy, value)
					end
					ft = copy
				end
				local variants = route_map[lhs]
				-- `rhs = false` (or `vim.NIL`) removes this plugin's entry
				-- from lazy.nvim's resolved handler map
				-- (lazy/core/handler/keys.lua: `values[keys.id] = nil`).
				-- Process entries in declaration order so a later `false`
				-- cancels an earlier real binding, while a later real
				-- binding re-adds it. A variant shared with other plugins
				-- only loses this plugin's id.
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
					local duplicate = false
					for k = 1, #variant.ids do
						if variant.ids[k] == plugin_id then
							duplicate = true
							break
						end
					end
					if not duplicate then
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

--- lazy.nvim fields that laze accepts but that have no vim.pack equivalent.
--- They are consumed (not passed through) and produce one warning per
--- field per compile so users know the config will not behave identically
--- on both managers (a notify costs ~180 us — no per-spec repeat).
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
		-- `submodules = true` (and the default) already matches vim.pack,
		-- which runs `git submodule update --init --recursive`. Only the
		-- opt-out is a real difference.
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

--- Trigger fields accept a subset of the lazy.nvim value shapes. Function-
--- shaped triggers (valid in lazy.nvim, evaluated at startup there) are
--- rejected: laze has no runtime evaluation, and silently normalizing them
--- to "no trigger" would turn the plugin eager — the worst failure mode.
local function validate_triggers(spec, idx, spec_id)
	local function bad(field, msg)
		require("laze.diag").bad(idx, spec_id, field, msg)
	end

	for _, field in ipairs(TRIGGER_FIELDS) do
		if type(spec[field]) == "function" then
			bad(field, "must be a string or array — function triggers are not supported by laze")
		end
		if spec[field] ~= nil and type(spec[field]) ~= "string" and type(spec[field]) ~= "table" then
			bad(field, "must be a string or array")
		end
		if spec[field] == "" then
			-- An empty trigger would match everything (FileType "") or
			-- raise at plan time (autocmd with event "").
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

		-- Single { event = ..., pattern = ... } table (lazy.nvim LazyEventSpec)
		-- as well as the array form.
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
		if type(spec[field]) == "table" then
			for i, item in ipairs(spec[field]) do
				if type(item) ~= "string" then
					bad(field .. "[" .. i .. "]", "must be a string")
				end
				if item == "" then
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
				-- lazy.nvim's LazyKeysSpec.rhs is string|fun|false (plus
				-- vim.NIL from a JSON null). Anything else used to fail at
				-- keypress time inside nvim_replace_termcodes; reject it at
				-- compile time instead.
				local rhs = item.rhs
				if rhs == nil then
					rhs = item[2]
				end
				local is_nil = rhs ~= nil and vim.NIL ~= nil and rhs == vim.NIL
				if
					rhs ~= nil
					and not is_nil
					and rhs ~= false
					and type(rhs) ~= "string"
					and type(rhs) ~= "function"
				then
					bad("keys[" .. i .. "].rhs", "must be a string, function, false, or vim.NIL")
				end
				if item.ft ~= nil then
					-- lazy.nvim: string|string[], used as the FileType
					-- autocmd pattern for a buffer-local trigger map.
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
				-- lazy.nvim does not validate the contents of mode:
				-- mode = "" is passed to vim.keymap.set (which creates a
				-- multi-mode mapping), and mode = {} resolves to no key
				-- handler while the plugin stays lazy. Match that behavior
				-- instead of rejecting empty values.
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
		if spec[f] ~= nil and (type(spec[f]) ~= "string" or spec[f] == "") then
			require("laze.diag").spec_at(idx, f .. " must be a non-empty string")
		end
	end

	local spec_id = tostring(src or spec.dir or spec.url)

	-- Every check below fails fatally (diag.spec raises). The closure keeps the
	-- inline lazy require from lua/laze/diag.lua (parsed only when a message
	-- actually fires) while leaving one short call per check.
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
		-- The two shapes are exclusive (err raises): the table form is
		-- lazy.nvim's removed opts alias, so it gets a message naming the
		-- replacements instead of the generic type error.
		if type(spec.config) == "table" then
			err("config = { ... } (lazy.nvim's deprecated opts alias) is not supported — use main = \"...\" with opts = {...}, or config = function() ... end")
		else
			err("config must be a function or true")
		end
	end
	-- opts is lazy.nvim's setup shorthand: a table (or a function returning
	-- one) passed to require(main).setup(opts) at load. main is resolved
	-- lazily like lazy.nvim (explicit, name match, or the single top-level
	-- module) because the plugin is not installed at compile time.
	if spec.opts ~= nil and type(spec.opts) ~= "table" and type(spec.opts) ~= "function" then
		err("opts must be a table or function")
	end
	if spec.main ~= nil and (type(spec.main) ~= "string" or spec.main == "") then
		err("main must be a non-empty string")
	end
	-- lazy.nvim accepts boolean or function for both cond and enabled.
	if spec.cond ~= nil and type(spec.cond) ~= "function" and type(spec.cond) ~= "boolean" then
		err("cond must be a function or boolean")
	end
	if spec.enabled ~= nil and type(spec.enabled) ~= "function" and type(spec.enabled) ~= "boolean" then
		err("enabled must be a function or boolean")
	end
	if spec.lazy ~= nil and type(spec.lazy) ~= "boolean" then
		err("lazy must be a boolean")
	end
	if spec.submodules ~= nil and type(spec.submodules) ~= "boolean" then
		err("submodules must be a boolean")
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
	if spec.dependencies ~= nil then
		if type(spec.dependencies) ~= "string" and type(spec.dependencies) ~= "table" then
			err("dependencies must be a string, name array, or spec array")
		elseif type(spec.dependencies) == "table" then
			for i, dep in ipairs(spec.dependencies) do
				if type(dep) ~= "string" and type(dep) ~= "table" then
					err("dependencies[" .. i .. "] must be a string or spec table")
				end
			end
		end
	end
	if spec.build ~= nil and type(spec.build) ~= "string" and type(spec.build) ~= "function" and spec.build ~= false then
		if type(spec.build) == "table" then
			for i, item in ipairs(spec.build) do
				if type(item) ~= "string" and type(item) ~= "function" then
					err("build[" .. i .. "] must be a string or function")
				end
			end
		else
			err("build must be a string, function, false, or a list of strings/functions")
		end
	end
	if spec.module ~= nil and type(spec.module) ~= "string" and type(spec.module) ~= "table" and spec.module ~= false then
		err("module must be a string, array, or false")
	end
	if type(spec.module) == "table" then
		if #spec.module == 0 then
			err("module must not be an empty array — use false or omit it")
		end
		for i, mod in ipairs(spec.module) do
			if type(mod) ~= "string" or mod == "" then
				err("module[" .. i .. "] must be a non-empty string")
			end
		end
	end
	if spec.priority ~= nil and type(spec.priority) ~= "number" then
		err("priority must be a number")
	end
	local version_range
	if spec.version ~= nil and spec.version ~= false then
		if type(spec.version) ~= "string" then
			err("version must be a string (semver range) or false")
		end
		-- lazy.nvim's precedence is commit > tag > version > branch, so a
		-- range that cannot win is not evaluated. Keep the type check above,
		-- but only parse when version is actually eligible. This also lets
		-- plain-Lua snapshot generation handle ref-only fixtures without a
		-- vim.version stub. Return the object so resolve_version can reuse it
		-- instead of parsing the same string twice. The semver module is
		-- required lazily: most configs have no `version` spec and never
		-- pay its parse cost at startup.
		--
		-- `dir` and an active dev source are local checkouts: lazy.nvim
		-- ignores version/refs for them, so do not reject a range that will
		-- never be lowered. This is a drop-in compatibility fix (KD-004).
		if spec.commit == nil and spec.tag == nil and spec.dir == nil and not has_dev_source(spec) then
			version_range = require("laze.semver").to_semver_range(spec.version, idx, spec_id)
		end
	end
	for _, f in ipairs(VERSION_REF_FIELDS) do
		if spec[f] ~= nil and (type(spec[f]) ~= "string" or spec[f] == "") then
			err(f .. " must be a non-empty string")
		end
	end

	validate_triggers(spec, idx, spec_id)
	return version_range
end

-- lazy.nvim's Util.is_list: a table whose keys are exactly 1..n. Empty
-- tables are lists too. This is what makes `{ { "foo/bar" } }` a nested
-- spec list rather than a spec with a table source.
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

--- Flatten lazy.nvim-shaped spec lists: a bare source string is shorthand
--- for `{ src }`, and a list may contain nested lists. Spec tables are kept
--- by reference (compile never mutates them). Mirrors Spec:normalize in
--- lazy.nvim so a config that works there does not crash here.
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

	-- Numeric-only keys that are not a dense list are a sparse list (for
	-- example { [1] = "foo", [3] = "bar" }). ipairs would silently drop the
	-- trailing element, so reject it instead.
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
---@param opts? { dev_root?: string }
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

	local dev_root = (opts and opts.dev_root) or "~/projects"

	-- Pass 1: index top-level names and resolved sources so dependency
	-- expansion can reference specs already defined by the user instead of
	-- re-registering them. lazy.nvim matches fragments by name and by URL;
	-- the source index is what keeps `{ "foo/baz", name = "bar" }` from
	-- being duplicated as `baz` when another spec depends on `"foo/baz"`.
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
	-- Known-difference messages are deduped per compile (issue #12). The
	-- closure is shared by dependency expansion and spec validation.
	local kd_notified = {}
	local function notify_kd(id, detail, key)
		-- Lazy-load: this path is rarely hit, so avoid paying the require cost at startup.
		require("laze.known_differences").notify(id, detail, kd_notified, opts, key)
	end
	-- Dependency-derived `after` names live in a side table, NOT on the
	-- user's spec tables: compile is a pure transform and must not mutate
	-- its input (the same spec table passed to lazy.nvim afterwards would
	-- carry a laze-only `after` field).
	local dep_after = {}

	--- Expand one spec's dependencies recursively. Inline dependency specs
	--- are registered once and their own dependencies are expanded first,
	--- so `after` always points at a registered id. Top-level names are
	--- referenced, not re-registered (lazy.nvim's "fragments" merge is
	--- outside laze's subset).
	---@param spec table
	---@param label string
	local function expand_dependencies(spec, label)
		-- lazy.nvim does not register dependencies of a plugin that is
		-- disabled at compile time (`enabled = false` / `cond = false`).
		-- Function-valued cond/enabled cannot be decided here, so keep the
		-- expansion for those and let the plan skip the parent.
		if spec.dependencies == nil or spec.enabled == false or spec.cond == false then
			return
		end
		-- Guard shapes here, before any derive/expand: validate_spec runs
		-- later (over `expanded`) and a malformed value would crash with a
		-- raw "attempt to index" error in this pass otherwise.
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
			-- Same derivation as the compile loop below: dir/url-only
			-- inline deps must resolve to the same id the registry uses.
			local dep_base = dep_spec[1] or dep_spec.src or dep_spec.dir or dep_spec.url
			local dep_name = dep_spec.name or derive_name(dep_base or "")
			local dep_src
			if dep_base then
				local ok, resolved = pcall(resolve_src, dep_spec[1] or dep_spec.src, dep_spec.dir, dep_spec.url)
				if ok then
					dep_src = resolved
				end
			end
			-- Prefer an existing top-level spec by name, then by resolved
			-- source (a renamed spec must not be re-registered under its
			-- repo-derived name), then an already-expanded dependency.
			local existing_top = (spec_names[dep_name] and dep_name) or (dep_src and spec_srcs[dep_src])
			local existing_expanded = (dep_src and expanded_srcs[dep_src])
				or (expanded_names[dep_name] and dep_name)
			local target = existing_top or existing_expanded or dep_name
			-- The same dep listed twice in one array (including two aliases
			-- that resolve to the same plugin) is wired once.
			local already_named = false
			for _, n in ipairs(dep_names) do
				if n == target then
					already_named = true
					break
				end
			end
			if not already_named then
				table.insert(dep_names, target)
				if not existing_top and not existing_expanded then
					-- Mark before recursing so a dependency cycle references
					-- the in-flight spec instead of recursing forever.
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

	-- Unsupported-field warnings are deduped per field per compile: a
	-- single vim.notify costs ~180 us headless, so N specs sharing one
	-- unsupported field would otherwise pay N× per startup for the same
	-- message. The first offending spec is named in the message.
	local warned = {}

	for idx, spec in ipairs(expanded) do
		local version_range = validate_spec(spec, idx, warned, notify_kd)

		local src = spec[1] or spec.src
		local dir = spec.dir
		local url = spec.url
		local base_src = src or dir or url
		local name = spec.name or derive_name(base_src)
		-- Directory name under pack/<pkg>/opt/ — matches vim.pack's own
		-- derivation unless the user pinned an explicit `name`.
		local pkg = pkg_name(base_src or name, spec.name)

		if registry[name] then
			-- Two specs producing the same id would silently drop the first
			-- spec's init/config/after while keeping its pack entry and
			-- trigger ids — refuse instead.
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

		-- Merge explicit `after` with dependency-derived names, in that
		-- order, without touching the user's spec table (compile purity).
		-- Dedup preserved: a dep named both ways is wired once.
		local after = dep_after[spec] or {}
		if spec.after then
			local merged = {}
			for _, n in ipairs(spec.after) do
				table.insert(merged, n)
			end
			for _, n in ipairs(after) do
				local already = false
				for _, existing in ipairs(merged) do
					if existing == n then
						already = true
						break
					end
				end
				if not already then
					table.insert(merged, n)
				end
			end
			after = merged
		end

		-- build = false means "no build" (lazy.nvim semantics). NOT
		-- `spec.build == false and nil or spec.build` — that Lua gotcha
		-- returns false again (nil can't flow through and/or).
		local build = spec.build
		if build == false or (type(build) == "table" and #build == 0) then
			build = nil
		end

		-- opts without config and config = true both desugar to
		-- require(main).setup(opts) at load. The main module is resolved
		-- at load time (like lazy.nvim) because a remote plugin is not
		-- installed yet during compile. The closure captures only pure
		-- values, so re-compiles are deterministic.
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
						("Lua module not found for config of %s. Please use a `config()` function instead"):format(
							plugin_name
						),
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

		-- Module name(s) that trigger lazy load on require(). Explicit only —
		-- never derived from the source, since repo names don't reliably match
		-- module names (cmp-buffer ships cmp_buffer).
		local modname = norm.module

		-- Resolve dev paths at compile time (once), not at plan/build time.
		-- `dev_src` also records that the source is a local checkout: an
		-- active dev path changes version handling below.
		local dev_src
		if norm.dev == true then
			dev_src = vim.fn.expand(dev_root .. "/" .. name)
		elseif type(norm.dev) == "string" and norm.dev ~= "" then
			-- dev = "path" is the per-plugin dev directory (lazy.nvim
			-- semantics): ~ expands, absolute/relative stay verbatim —
			-- consistent with dev_path and the README notes.
			dev_src = expand_home(norm.dev)
		elseif norm.dev_path then
			dev_src = expand_home(norm.dev_path)
		end
		local final_src = dev_src or resolved_src

		-- `dir` plugins are local: vim.pack never installs or manages them
		-- (it would try to git-clone the path). They are loaded by the plan
		-- via :packadd / rtp prepend, mirroring lazy.nvim `dir` semantics.
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
			-- not is_local and pkg or nil — NOT "is_local and nil or pkg"
			-- (that Lua gotcha always evaluates to pkg: nil can't flow
			-- through `and/or`). Local dir plugins have no pack entry.
			pkg = (not is_local) and pkg or nil,
		}

		if is_local then
			if norm.build ~= nil then
				require("laze.diag").warn(
					"plugin '"
						.. name
						.. "' is a local dir; build is not run (vim.pack does not install or rebuild local dirs)"
				)
			end
		else
			local pack_entry = {
				src = final_src,
				-- The installed directory is `pack/<pkg>/opt/<name>`, so the
				-- name must match vim.pack's own derivation (pkg_name) for
				-- existing installs to keep working. The registry id may
				-- differ (dotted repos: id "which-key" vs dir "which-key.nvim")
				-- and must never be used for :packadd.
				name = pkg,
			}
			-- An active dev path is a local, unmanaged checkout: lazy.nvim
			-- turns `dev` into `dir` and never applies version/branch/tag/
			-- commit to it. Lowering one here would make vim.pack clone the
			-- dev path and check out that ref instead of loading the working
			-- tree — the exact bug this guard prevents. Same policy as `dir`
			-- (validate the range, never lower it; validate_spec already ran).
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
			if spec.build ~= nil and spec.build ~= false then
				pack_entry.build = spec.build
			end
			-- remaining unknown fields still pass through for forward compat
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

	-- Entries referenced as `after` deps are never eager: they load via
	-- their parents (eager parents pull them at startup, lazy parents at
	-- trigger time). Shared by init.lua (pack split) and plan.lua (eager
	-- list) so both agree on what "eager" means.
	local is_dep = {}
	for _, entry in pairs(registry) do
		for _, dep_id in ipairs(entry.after or {}) do
			is_dep[dep_id] = true
		end
	end
	for id, entry in pairs(registry) do
		entry.is_dep = is_dep[id] == true
		-- lazy.nvim's `lazy` flag is an explicit override:
		--   false -> eager even when triggers/dependency status say lazy
		--   true  -> never eager, even without triggers
		--   nil   -> laze's default: eager only without triggers and not a dep
		entry.eager = entry.lazy == false
			or (entry.lazy ~= true and not entry.has_route and not entry.is_dep)
	end

	return {
		pack = pack,
		registry = registry,
		routes = routes,
	}
end

-- Pure helpers are exported for the standalone unit tests
-- (tests/test_compile.lua, tests/test_subset.lua) and extras.
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
