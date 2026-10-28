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
local function derive_name(src)
	-- lazy.nvim-compatible (lazy/core/plugin.lua Spec.get_name): strip a
	-- trailing `.git`, then one trailing slash, then take the last path
	-- segment. Without the braces, "user/repo.git" keeps the .git suffix
	-- and "…/plugin/" (trailing slash) falls back to the raw URL as id.
	local name = src
	if name:sub(-1) == "/" then
		name = name:sub(1, -2)
	end
	if name:sub(-4) == ".git" then
		name = name:sub(1, -5)
	end
	name = last_segment(name) or name
	if name:sub(-5) == ".nvim" then
		name = name:sub(1, -6)
	end
	if name:sub(-4) == ".lua" then
		name = name:sub(1, -5)
	end
	return name
end

-- lazy.nvim's Util.normname: used to match a plugin name against the
-- top-level Lua modules it ships. Kept byte-for-byte equivalent to
-- lazy/core/util.lua so main-module resolution picks the same module.
local function norm_module_name(name)
	return name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("[^a-z]+", "")
end

--- Resolve a plugin's `main` module the way lazy.nvim does when `opts` or
--- `config = true` is used without an explicit `main`:
---   * `mini.<name>` plugins use their own name (except `mini.nvim`),
---   * otherwise scan the top-level entries under `<plugin>/lua`, prefer a
---     module whose normalized name matches the plugin name, and fall back
---     to the single module when the plugin ships exactly one.
--- Runs at load time (the plugin is installed by then), never at compile.
---@param plugin_dir string?
---@param name string
---@return string?
local function get_main(plugin_dir, name)
	if name ~= "mini.nvim" and name:match("^mini%.") then
		return name
	end
	if not plugin_dir then
		return nil
	end
	local uv = vim.uv or vim.loop
	local lua_dir = plugin_dir .. "/lua"
	local handle = uv.fs_scandir(lua_dir)
	if not handle then
		return nil
	end
	local normname = norm_module_name(name)
	local mods = {}
	local seen = {}
	while true do
		local entry_name, t = uv.fs_scandir_next(handle)
		if not entry_name then
			break
		end
		local topname
		local ext = entry_name:sub(-4)
		if ext == ".lua" or ext == ".dll" then
			topname = entry_name:sub(1, -5)
		elseif entry_name:sub(-3) == ".so" then
			topname = entry_name:sub(1, -4)
		elseif t == "link" or t == "directory" then
			topname = entry_name
		elseif t == nil then
			-- luv occasionally omits the type; stat it like lazy.nvim does.
			local st = uv.fs_stat(lua_dir .. "/" .. entry_name)
			if st and (st.type == "link" or st.type == "directory") then
				topname = entry_name
			end
		end
		if topname and not seen[topname] then
			seen[topname] = true
			if norm_module_name(topname) == normname then
				return topname
			end
			table.insert(mods, topname)
		end
	end
	return #mods == 1 and mods[1] or nil
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
	local name = src
	if name:sub(-1) == "/" then
		name = name:sub(1, -2)
	end
	if name:sub(-4) == ".git" then
		name = name:sub(1, -5)
	end
	return last_segment(name) or name
end

local function resolve_src(src, dir, url)
	if dir then
		-- Byte test, not `:match("^~")`: patterns are NYI in LuaJIT and
		-- run interpreted (~50 ns vs sub-ns per call on this hot path).
		if dir:byte(1) == 126 then -- "~"
			return vim.fn.expand(dir)
		end
		return dir
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
				table.insert(result, {
					lhs = item.lhs or item[1],
					mode = item.mode or "n",
					-- rhs: string (feedkeys) or function (opaque callback)
					rhs = item.rhs or item[2],
					-- lazy.nvim key options (passed to vim.keymap.set)
					desc = item.desc,
					silent = item.silent,
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

-- lazy.nvim's `version` is a semver range, not a git ref. vim.version.range
-- is lenient enough to misparse refs ("abc123" → 123.0.0), drop everything
-- after the first comparator ("1.2 || 1.3", ">=1.2.0 <2.0.0"), and ignore
-- trailing junk. Validate the whole string before handing it to vim.pack so
-- an unrepresentable range fails at compile time instead of silently
-- narrowing. Refs belong in branch/tag/commit.
local function is_digit(b)
	return b ~= nil and b >= 48 and b <= 57
end

local function is_wildcard(b)
	return b == 42 or b == 120 or b == 88 -- * x X
end

local function is_ident_byte(b)
	return b ~= nil
		and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 45)
end

-- Scan one version token after an optional comparator. Accepts the shapes
-- lazy.nvim/vim.version.range support: partial versions, x/X/* wildcards,
-- prerelease, and build metadata. Returns false on any trailing bytes.
local function is_version_token(s, i)
	local n = #s
	local b = s:byte(i)
	if b == 118 or b == 86 then -- v / V
		i = i + 1
	end
	if not is_digit(s:byte(i)) then
		return false
	end

	local numeric = 0
	local wildcard = false
	while i <= n do
		b = s:byte(i)
		if is_digit(b) then
			if wildcard then
				return false -- no numeric component after a wildcard
			end
			repeat
				i = i + 1
			until not is_digit(s:byte(i))
			numeric = numeric + 1
		elseif is_wildcard(b) then
			wildcard = true
			i = i + 1
		else
			break
		end
		if s:byte(i) == 46 then -- "."
			i = i + 1
			if i > n then
				return false
			end
		else
			break
		end
	end
	if numeric == 0 or numeric > 3 then
		return false
	end

	-- Prerelease/build after a wildcard would be stripped by vim.version.range
	-- along with the wildcard, so reject it rather than guess.
	if wildcard and (s:byte(i) == 45 or s:byte(i) == 43) then
		return false
	end

	local function scan_identifiers(j, stop_at_plus)
		local start = j
		while j <= n do
			local bb = s:byte(j)
			if is_ident_byte(bb) then
				j = j + 1
			elseif bb == 46 then -- "."
				if j == start or s:byte(j - 1) == 46 then
					return false
				end
				j = j + 1
				if not is_ident_byte(s:byte(j)) then
					return false
				end
			elseif bb == 43 and stop_at_plus then -- "+"
				break
			else
				return false
			end
		end
		if j == start then
			return false
		end
		return j
	end

	if s:byte(i) == 45 then -- "-" prerelease
		i = scan_identifiers(i + 1, true)
		if i == false then
			return false
		end
	end
	if s:byte(i) == 43 then -- "+" build
		i = scan_identifiers(i + 1, false)
		if i == false then
			return false
		end
	end
	return i > n
end

local function is_range_operand(s, allow_comparator)
	local i = 1
	if allow_comparator then
		local b = s:byte(i)
		if b == 62 or b == 60 then -- > <
			if s:byte(i + 1) == 61 then -- >= <=
				i = i + 2
			else
				i = i + 1
			end
		elseif b == 94 or b == 126 or b == 61 then -- ^ ~ =
			i = i + 1
		end
	end
	return is_version_token(s, i)
end

local function looks_like_semver_range(v)
	local n = #v
	if n == 0 then
		return true -- lazy.nvim and vim.version.range treat "" as "*"
	end
	if n == 1 and v:byte(1) == 42 then -- "*"
		return true
	end

	-- The only whitespace accepted is a single hyphen-range separator. This
	-- rejects compound ranges (" >=1.2.0 <2.0.0") instead of letting
	-- vim.version.range keep only the first comparator.
	local hyphen = v:find(" - ", 1, true)
	if hyphen then
		if v:find(" - ", hyphen + 3, true) then
			return false
		end
		local a = v:sub(1, hyphen - 1)
		local b = v:sub(hyphen + 3)
		return a ~= "" and b ~= "" and is_range_operand(a, false) and is_range_operand(b, false)
	end
	for i = 1, n do
		local b = v:byte(i)
		if b == 32 or b == 9 or b == 10 or b == 13 then
			return false
		end
	end
	return is_range_operand(v, true)
end

---@param v string
---@param idx? integer
---@param spec_id? string
---@return vim.VersionRange
local function to_semver_range(v, idx, spec_id)
	local prefix = idx and ("spec [" .. idx .. "]" .. (spec_id and (" (" .. spec_id .. ")") or "") .. ": ") or ""
	if not looks_like_semver_range(v) then
		error(
			prefix
				.. ("version %q is not a supported semver range (single ranges only; multi-range/whitespace sets are rejected; git refs belong in branch/tag/commit)"):format(
					v
				),
			0
		)
	end
	local range_fn = vim.version and vim.version.range
	if type(range_fn) ~= "function" then
		error(prefix .. "vim.version.range is required to lower version ranges", 0)
	end
	local ok, range = pcall(range_fn, v)
	if not ok or range == nil then
		error(prefix .. ("version %q is not a valid semver range"):format(v), 0)
	end
	return range
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
		return range or to_semver_range(v, idx)
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
		local variants = route_map[lhs]
		if not variants then
			variants = {}
			route_map[lhs] = variants
		end
		local modes = type(ke.mode) == "table" and ke.mode or { ke.mode }
		local seen_modes = {}
		for j = 1, #modes do
			local mode = modes[j]
			-- `mode = { "n", "n" }`: one variant, not two maps for one lhs.
			if not seen_modes[mode] then
				seen_modes[mode] = true
				local variant
				for k = 1, #variants do
					if variants[k].mode == mode then
						variant = variants[k]
						break
					end
				end
				if not variant then
					variant = { mode = mode, ids = {}, rhs = ke.rhs, desc = ke.desc, silent = ke.silent }
					table.insert(variants, variant)
				elseif variant.rhs ~= ke.rhs or variant.desc ~= ke.desc or variant.silent ~= ke.silent then
					vim.notify(
						("laze: keys %q in mode %q is shared by multiple plugins with different rhs/opts — keeping the first"):format(
							lhs,
							mode
						),
						vim.log.levels.WARN
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
	submodules = "no equivalent; vim.pack fetches submodules by default",
	optional = "deps are always required; remove 'optional'",
	import = "lazy.nvim-only; load spec files yourself and pass the tables to setup",
	lazy = "no equivalent; plugins without triggers are eager",
	specs = "no equivalent; inline your specs instead",
}

local function warn_unsupported(spec, idx, spec_id, warned)
	for field, reason in pairs(UNSUPPORTED_FIELDS) do
		if spec[field] ~= nil and not warned[field] then
			warned[field] = true
			vim.notify(
				("laze: spec [%d] (%s): '%s' is not supported by laze (%s)"):format(idx, spec_id, field, reason),
				vim.log.levels.WARN
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
		error(("spec [%d] (%s): %s %s"):format(idx, spec_id, field, msg), 0)
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
				if item.mode ~= nil then
					if type(item.mode) == "string" then
						if item.mode == "" then
							bad("keys[" .. i .. "]", "mode must not be empty")
						end
					elseif not is_string_array(item.mode) then
						bad("keys[" .. i .. "]", "mode must be a string or string[]")
					elseif #item.mode == 0 then
						-- An empty mode set would create no trigger map at all
						-- while still marking the plugin lazy — a silent drop.
						bad("keys[" .. i .. "]", "mode must not be an empty array")
					else
						for _, m in ipairs(item.mode) do
							if m == "" then
								bad("keys[" .. i .. "]", "mode must not be empty")
							end
						end
					end
				end
			elseif type(item) ~= "string" then
				bad("keys[" .. i .. "]", "must be a string or an entry table")
			elseif item == "" then
				bad("keys[" .. i .. "]", "must not be empty")
			end
		end
	end
end

--- A `dev`/`dev_path` source is a local checkout, just like `dir`.
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
---@return vim.VersionRange|nil
local function validate_spec(spec, idx, warned)
	local src = spec[1] or spec.src
	if not src and not spec.dir and not spec.url then
		error("spec [" .. idx .. "]: missing source — use [1], .src, .dir, or .url", 0)
	end
	if src ~= nil and (type(src) ~= "string" or src == "") then
		error("spec [" .. idx .. "]: [1]/src must be a non-empty string", 0)
	end
	for _, f in ipairs(SOURCE_FIELDS) do
		if spec[f] ~= nil and (type(spec[f]) ~= "string" or spec[f] == "") then
			error("spec [" .. idx .. "]: " .. f .. " must be a non-empty string", 0)
		end
	end

	local spec_id = tostring(src or spec.dir or spec.url)

	warn_unsupported(spec, idx, spec_id, warned)

	if spec.dev == "" then
		vim.notify("laze: spec [" .. idx .. "] (" .. spec_id .. ") has dev='' — ignored", vim.log.levels.WARN)
	end

	if spec.init ~= nil and type(spec.init) ~= "function" then
		error("spec [" .. idx .. "] (" .. spec_id .. "): init must be a function", 0)
	end
	if spec.config ~= nil and type(spec.config) ~= "function" and spec.config ~= true then
		error("spec [" .. idx .. "] (" .. spec_id .. "): config must be a function or true", 0)
	end
	-- opts is lazy.nvim's setup shorthand: a table (or a function returning
	-- one) passed to require(main).setup(opts) at load. main is resolved
	-- lazily like lazy.nvim (explicit, name match, or the single top-level
	-- module) because the plugin is not installed at compile time.
	if spec.opts ~= nil and type(spec.opts) ~= "table" and type(spec.opts) ~= "function" then
		error("spec [" .. idx .. "] (" .. spec_id .. "): opts must be a table or function", 0)
	end
	if spec.main ~= nil and (type(spec.main) ~= "string" or spec.main == "") then
		error("spec [" .. idx .. "] (" .. spec_id .. "): main must be a non-empty string", 0)
	end
	-- lazy.nvim accepts boolean or function for both cond and enabled.
	if spec.cond ~= nil and type(spec.cond) ~= "function" and type(spec.cond) ~= "boolean" then
		error("spec [" .. idx .. "] (" .. spec_id .. "): cond must be a function or boolean", 0)
	end
	if spec.enabled ~= nil and type(spec.enabled) ~= "function" and type(spec.enabled) ~= "boolean" then
		error("spec [" .. idx .. "] (" .. spec_id .. "): enabled must be a function or boolean", 0)
	end
		if spec.after ~= nil then
		if type(spec.after) ~= "table" then
			error("spec [" .. idx .. "] (" .. spec_id .. "): after must be an array of plugin ids", 0)
		end
		for i, dep_id in ipairs(spec.after) do
			if type(dep_id) ~= "string" or dep_id == "" then
				error("spec [" .. idx .. "] (" .. spec_id .. "): after[" .. i .. "] must be a non-empty plugin id string", 0)
			end
		end
	end
	if spec.dependencies ~= nil then
		local is_str = type(spec.dependencies) == "string"
		local is_arr = type(spec.dependencies) == "table"
		if not is_str and not is_arr then
			error("spec [" .. idx .. "] (" .. spec_id .. "): dependencies must be a string, name array, or spec array", 0)
		end
		if is_arr then
			for i, dep in ipairs(spec.dependencies) do
				if type(dep) ~= "string" and type(dep) ~= "table" then
					error("spec [" .. idx .. "] (" .. spec_id .. "): dependencies[" .. i .. "] must be a string or spec table", 0)
				end
			end
		end
	end
	if spec.build ~= nil and type(spec.build) ~= "string" and type(spec.build) ~= "function" and spec.build ~= false then
		if type(spec.build) == "table" then
			for i, item in ipairs(spec.build) do
				if type(item) ~= "string" and type(item) ~= "function" then
					error(
						"spec ["
							.. idx
							.. "] ("
							.. spec_id
							.. "): build["
							.. i
							.. "] must be a string or function",
						0
					)
				end
			end
		else
			error(
				"spec ["
					.. idx
					.. "] ("
					.. spec_id
					.. "): build must be a string, function, false, or a list of strings/functions",
				0
			)
		end
	end
		if
		spec.module ~= nil
		and type(spec.module) ~= "string"
		and type(spec.module) ~= "table"
		and spec.module ~= false
	then
		error("spec [" .. idx .. "] (" .. spec_id .. "): module must be a string, array, or false", 0)
	end
	if type(spec.module) == "table" then
		if #spec.module == 0 then
			error("spec [" .. idx .. "] (" .. spec_id .. "): module must not be an empty array — use false or omit it", 0)
		end
		for i, mod in ipairs(spec.module) do
			if type(mod) ~= "string" or mod == "" then
				error("spec [" .. idx .. "] (" .. spec_id .. "): module[" .. i .. "] must be a non-empty string", 0)
			end
		end
	end
	if spec.priority ~= nil and type(spec.priority) ~= "number" then
		error("spec [" .. idx .. "] (" .. spec_id .. "): priority must be a number", 0)
	end
	local version_range
	if spec.version ~= nil and spec.version ~= false then
		if type(spec.version) ~= "string" then
			error("spec [" .. idx .. "] (" .. spec_id .. "): version must be a string (semver range) or false", 0)
		end
		-- lazy.nvim's precedence is commit > tag > version > branch, so a
		-- range that cannot win is not evaluated. Keep the type check above,
		-- but only parse when version is actually eligible. This also lets
		-- plain-Lua snapshot generation handle ref-only fixtures without a
		-- vim.version stub. Return the object so resolve_version can reuse it
		-- instead of parsing the same string twice.
		--
		-- `dir` and an active dev source are local checkouts: lazy.nvim
		-- ignores version/refs for them, so do not reject a range that will
		-- never be lowered. This is a drop-in compatibility fix (KD-004).
		if spec.commit == nil and spec.tag == nil and spec.dir == nil and not has_dev_source(spec) then
			version_range = to_semver_range(spec.version, idx, spec_id)
		end
	end
	for _, f in ipairs(VERSION_REF_FIELDS) do
		if spec[f] ~= nil and (type(spec[f]) ~= "string" or spec[f] == "") then
			error("spec [" .. idx .. "] (" .. spec_id .. "): " .. f .. " must be a non-empty string", 0)
		end
	end

	validate_triggers(spec, idx, spec_id)
	return version_range
end

---@param specs LazeSpec[]
---@param opts? { dev_root?: string }
---@return LazeCompiled
function compile(specs, opts)
	if type(specs) ~= "table" or #specs == 0 then
		error("compile: expected a non-empty array of specs", 0)
	end
	-- #specs only counts the dense prefix: {[1]=a,[3]=b} has # == 1 and
	-- ipairs would silently drop b — reject any non-array keys outright.
	local count = 0
	for _ in pairs(specs) do
		count = count + 1
	end
	if count ~= #specs then
		error("compile: spec array must not be sparse", 0)
	end
	for i = 1, #specs do
		if type(specs[i]) ~= "table" then
			error("compile: specs[" .. i .. "] must be a spec table", 0)
		end
	end

	local dev_root = (opts and opts.dev_root) or "~/dev"

	-- Pass 1: index top-level names so dependency expansion can reference
	-- specs already defined by the user instead of re-registering them.
	local spec_names = {}
	for _, spec in ipairs(specs) do
		local base = spec[1] or spec.src or spec.dir or spec.url
		if spec.name then
			spec_names[spec.name] = true
		elseif base then
			spec_names[derive_name(base)] = true
		end
	end

	local expanded = {}
	local expanded_names = {}
	-- Dependency-derived `after` names live in a side table, NOT on the
	-- user's spec tables: compile is a pure transform and must not mutate
	-- its input (the same spec table passed to lazy.nvim afterwards would
	-- carry a laze-only `after` field).
	local dep_after = {}
	for idx, spec in ipairs(specs) do
		if spec.dependencies then
			-- Guard shapes here, before any derive/expand: validate_spec runs
			-- later (over `expanded`) and a malformed value would crash with
			-- a raw "attempt to index" error in this pass otherwise.
			if type(spec.dependencies) ~= "string" and type(spec.dependencies) ~= "table" then
				error("spec [" .. idx .. "]: dependencies must be a string, name array, or spec array", 0)
			end
			local deps = type(spec.dependencies) == "table" and spec.dependencies or { spec.dependencies }
			local dep_names = {}
			for i, dep in ipairs(deps) do
				if type(dep) ~= "string" and type(dep) ~= "table" then
					error("spec [" .. idx .. "]: dependencies[" .. i .. "] must be a string or spec table", 0)
				end
				local dep_spec = type(dep) == "string" and { dep } or dep
				-- Same derivation as the compile loop below: dir/url-only
				-- inline deps must resolve to the same id the registry uses.
				local dep_name = dep_spec.name
					or derive_name(dep_spec[1] or dep_spec.src or dep_spec.dir or dep_spec.url or "")
				if dep_spec.dependencies then
					-- Dependencies of dependencies are not expanded
					-- (documented as shallow) — warn so the silent drop is
					-- not a surprise (lazy.nvim expands them).
					vim.notify(
						("laze: dependency %q (inline spec) has its own `dependencies` field — nested dependencies are not expanded; move it to the top-level spec list"):format(
							dep_name
						),
						vim.log.levels.WARN
					)
				end
				-- The same dep listed twice in one array is wired once.
				local already_named = false
				for _, n in ipairs(dep_names) do
					if n == dep_name then
						already_named = true
						break
					end
				end
				if not already_named and spec_names[dep_name] then
					-- Dep already defined elsewhere as a full spec: reference
					-- it via `after` only, don't re-register (lazy.nvim behavior).
					table.insert(dep_names, dep_name)
				elseif not already_named and not expanded_names[dep_name] then
					table.insert(dep_names, dep_name)
					table.insert(expanded, dep_spec)
					expanded_names[dep_name] = true
				elseif not already_named then
					-- Dep already expanded from another spec's dependencies.
					table.insert(dep_names, dep_name)
				end
			end
			dep_after[spec] = dep_names
		end
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
		local version_range = validate_spec(spec, idx, warned)

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
				config = function(plugin, opts)
					local main = explicit_main or get_main(plugin and plugin.dir, plugin_name)
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
					mod.setup(opts or {})
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
			if norm.dev:byte(1) == 126 then -- "~"
				dev_src = vim.fn.expand(norm.dev)
			else
				dev_src = norm.dev
			end
		elseif norm.dev_path then
			if norm.dev_path:byte(1) == 126 then -- "~"
				dev_src = vim.fn.expand(norm.dev_path)
			else
				dev_src = norm.dev_path
			end
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
			has_route = false, -- set below
			-- not is_local and pkg or nil — NOT "is_local and nil or pkg"
			-- (that Lua gotcha always evaluates to pkg: nil can't flow
			-- through `and/or`). Local dir plugins have no pack entry.
			pkg = (not is_local) and pkg or nil,
		}

		if is_local then
			if norm.build ~= nil then
				vim.notify(
					"laze: plugin '"
						.. name
						.. "' is a local dir; build is not run (vim.pack does not install or rebuild local dirs)",
					vim.log.levels.WARN
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
			local modules = type(norm.module) == "table" and norm.module or { norm.module }
			for _, mod in ipairs(modules) do
				if not routes.modules[mod] then
					routes.modules[mod] = {}
				end
				table.insert(routes.modules[mod], name)
			end
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
				vim.notify(
					"laze: plugin '" .. id .. "' has after dependency on '" .. dep_id .. "' which does not exist",
					vim.log.levels.WARN
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
	for id in pairs(registry) do
		registry[id].is_dep = is_dep[id] == true
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
