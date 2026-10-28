--- test_subset.lua — verify laze's spec surface stays a lazy.nvim subset.
--- Run: luajit tests/test_subset.lua
---
--- The escape-hatch principle (see AGENTS.md): a config written for laze
--- should work in lazy.nvim with little or no changes. This test pins that
--- property as data: every field name laze consumes must be a documented
--- lazy.nvim spec field, or an explicitly justified exception. It also pins
--- value-level version semantics (semver range vs git ref, precedence).

package.path = string.format("./lua/?.lua;%s", package.path)

-- Minimal vim stub (same shape as tests/test_compile.lua).
-- The stub deliberately mirrors vim.version.range's real misparses for
-- refs/multi-ranges so the shape guard in compile.lua is actually tested.
local range_calls = {}
local misparsed_ranges = {
	["abc123"] = "RANGE(abc123)", -- real vim.version.range → 123.0.0 - 124.0.0
	["1.2 || 1.3"] = "RANGE(1.2 || 1.3)", -- real vim.version.range → first range only
}
vim = {}
vim.log = { levels = { WARN = "WARN" } }
vim.notify = function() end
vim.version = {
	range = function(v)
		table.insert(range_calls, v)
		if v == "main" then
			return nil
		end
		return misparsed_ranges[v] or ("RANGE(" .. v .. ")")
	end,
}

local compile_mod = require("laze.compile")
local consumed = compile_mod.CONSUMED_KEYS
local unsupported = compile_mod.UNSUPPORTED_FIELDS

-- lazy.nvim spec fields — authoritative source: https://lazy.folke.io/spec
-- (fetched 2026-08-18, grouped by the doc's own sections).
local LAZY_NVIM_FIELDS = {
	-- Spec Source
	["[1]"] = "short plugin url / dir / url",
	src = "same as [1]",
	dir = "local plugin directory",
	url = "custom git url",
	name = "custom name for dir + display",
	dev = "boolean — use local dev directory",
	-- Spec Loading
	dependencies = "LazySpec[] — always lazy-loaded unless specified otherwise",
	enabled = "boolean|fun():boolean",
	cond = "boolean|fun(LazyPlugin):boolean",
	priority = "number — start-plugin load order (higher first), default 50",
	-- Spec Setup
	init = "fun(LazyPlugin) — always executed during startup",
	opts = "table|fun(LazyPlugin, opts) — implies config()",
	config = "fun(LazyPlugin, opts)|true",
	main = "string — module used by config()/opts()",
	build = "fun|string|false|list of build commands",
	-- Spec Lazy Loading
	lazy = "boolean",
	event = "string|string[]|{event,pattern}[]|fun",
	cmd = "string|string[]|fun",
	ft = "string|string[]|fun",
	keys = "string|string[]|LazyKeysSpec[]|fun",
	-- Spec Versioning
	branch = "string",
	tag = "string",
	commit = "string",
	version = "string|false — semver range (git refs use branch/tag/commit)",
	pin = "boolean — exclude from updates",
	submodules = "boolean",
	-- Spec Advanced
	optional = "boolean — only included when the same plugin is defined non-optional elsewhere",
	specs = "LazySpec — scoped specs, no automatic loading",
	module = "false — do not auto-load the Lua module on require",
	import = "string — import a spec module",
}

-- lazy.nvim fields passed through to vim.pack UNCONSUMED (not read by
-- laze at all): they must not appear in CONSUMED_KEYS, and the subset
-- test treats them as "handled by vim.pack", not ignored.
local PASSTHROUGH_FIELDS = {
	pin = "vim.pack.Spec.pin — exclude from updates",
}

-- laze-only fields. Every entry needs a justification:
--   kind = "extension" → laze-specific; must be *safe* to ignore in lazy.nvim
--   kind = "vim.pack"  → vim.pack.Spec passthrough
local LAZE_ONLY_FIELDS = {
	after = {
		kind = "extension",
		note = "dep ordering (load me after X). lazy.nvim equivalent: dependencies. Silently ignored by lazy.nvim — convert to dependencies on migration.",
	},
	data = {
		kind = "vim.pack",
		note = "vim.pack.Spec.data — arbitrary data carried on the pack entry",
	},
	dev_path = {
		kind = "extension",
		note = "per-plugin dev directory used with dev=true. Not in the current lazy.nvim spec docs (config.dev.path covers it); ignored by lazy.nvim.",
	},
	silent = {
		kind = "extension",
		note = "suppress vim.notify warnings on require failure. lazy.nvim has silent only on keys entries; the top-level field is laze-specific.",
	},
}

local passed = 0
local failed = 0

local function pass(label)
	passed = passed + 1
	print(("  \xe2\x9c\x93 %s"):format(label))
end

local function fail(label, detail)
	failed = failed + 1
	print(("  \xe2\x9c\x97 %s\n    %s"):format(label, detail))
end

print("=== subset: laze spec fields vs lazy.nvim spec fields ===\n")

-- Every laze-consumed field must be a lazy.nvim field or a justified exception.
local shared, extensions, passthroughs = {}, {}, {}
for key in pairs(consumed) do
	if LAZY_NVIM_FIELDS[key] then
		table.insert(shared, key)
	elseif LAZE_ONLY_FIELDS[key] then
		local just = LAZE_ONLY_FIELDS[key]
		if just.kind == "extension" then
			table.insert(extensions, key)
		elseif just.kind == "vim.pack" then
			table.insert(passthroughs, key)
		else
			fail(("field %q: invalid justification kind %q"):format(key, tostring(just.kind)), "kinds allowed: extension | vim.pack")
		end
		if just.kind == "extension" and not just.note then
			fail(("field %q: extension without a note"):format(key), "add a note explaining the lazy.nvim migration path")
		end
	else
		fail(("field %q is consumed by laze but is NOT a lazy.nvim spec field"):format(key), "add it to LAZY_NVIM_FIELDS or justify it in LAZE_ONLY_FIELDS")
	end
end

-- Warned-but-unsupported fields must reference real lazy.nvim fields,
-- otherwise the warning text is misleading.
for key in pairs(unsupported) do
	if not LAZY_NVIM_FIELDS[key] then
		fail(("unsupported field %q is not a lazy.nvim field"):format(key), "remove it from UNSUPPORTED_FIELDS in compile.lua")
	end
end

table.sort(shared)
table.sort(extensions)
table.sort(passthroughs)

-- Every lazy.nvim field must be at least consumed (positional [1] and
-- passthrough fields exempt): an unconsumed lazy.nvim field would fall
-- into the vim.pack passthrough and go silently ignored everywhere.
local ignored_by_laze = {}
for key in pairs(LAZY_NVIM_FIELDS) do
	if key ~= "[1]" and not consumed[key] and not PASSTHROUGH_FIELDS[key] then
		table.insert(ignored_by_laze, key)
	end
end
table.sort(ignored_by_laze)
if #ignored_by_laze > 0 then
	fail("lazy.nvim fields neither consumed nor warned:", table.concat(ignored_by_laze, ", "))
else
	pass("every documented lazy.nvim field is consumed or warned by laze")
end

local passthrough_keys = {}
for k in pairs(PASSTHROUGH_FIELDS) do
	table.insert(passthrough_keys, k)
end
table.sort(passthrough_keys)

print(("\n  shared with lazy.nvim (%d): %s"):format(#shared, table.concat(shared, ", ")))
print(("  passthrough to vim.pack (%d): %s"):format(#passthrough_keys, table.concat(passthrough_keys, ", ")))
print(("  laze extensions (%d): %s"):format(#extensions, table.concat(extensions, ", ")))
for _, key in ipairs(extensions) do
	print(("    - %s: %s"):format(key, LAZE_ONLY_FIELDS[key].note))
end
print(("  vim.pack passthrough (%d): %s"):format(#passthroughs, table.concat(passthroughs, ", ")))

print("\n=== subset: semantic notes (soft) ===\n")

-- Field names are only half the story; value-level semantics differ in a few
-- places. These are reported, not asserted — they are deliberate design
-- choices with a safe direction (lazy.nvim accepts the laze value shape).

local notes = {
	"module: lazy.nvim accepts only false (opt-out of auto require-loading). laze accepts string|string[] as opt-in require triggers; module=false in a laze spec simply means 'no triggers'.",
	"version: lazy.nvim = semver range (a string like '*' or '>=2.0.0', or false); branch/tag/commit are git refs. laze lowers a version string to vim.version.range and a ref to a vim.pack version string, with lazy.nvim precedence commit > tag > version > branch. version=false falls through to branch (or vim.pack's default). Only a single range is accepted (no '||' or whitespace-separated comparator sets); a prebuilt vim.VersionRange is rejected. A range overridden by tag/commit is not parsed.",
	"config = true: valid in lazy.nvim (implies opts support); laze raises a clear error instead of silently misbehaving — safe direction.",
	"build: lazy.nvim accepts false (skip build) and a list of commands. laze accepts false (no-op, same as omitting it) and a single string/function; the list form is rejected with a compile error — safe direction.",
	"priority: honored for eager ordering — eager plugins load highest-first with id as tie-break, matching lazy.nvim's start-plugin reordering. Dependencies (`after`) never order eagerly: they load via their parents.",
	"keys entries: laze keeps lhs/rhs/mode/desc/silent; other vim.keymap.set options (noremap, nowait, expr, callback, buffer) are silently dropped.",
	"function-shaped triggers (event/cmd/ft/keys = fun(self, list)): valid in lazy.nvim (evaluated at startup). laze REJECTS them with a compile error — silently ignoring them would turn the plugin eager. Rejecting is the safe direction: a laze config never contains them, and migrating laze → lazy.nvim is unaffected.",
	"keys mode: laze accepts mode = string | string[] ('n','v',...); lazy.nvim's LazyKeysSpec mode also accepts a mode table. Shared shape.",
	"dev = string: laze uses it as the dev directory. lazy.nvim documents dev as boolean only (a string is truthy there and triggers config.dev.path).",
}

for _, note in ipairs(notes) do
	print(("  - %s"):format(note))
end

print("\n=== subset: semantic conformance (version) ===\n")

-- Field names are not enough: version is a semver range in lazy.nvim, while
-- branch/tag/commit are git refs. Pin the lowering and precedence here so a
-- vim.pack-shaped redefinition (version = ref) fails this test.
local resolve_version = compile_mod.resolve_version

local function version_case(spec, expected, label)
	local ok, got = pcall(resolve_version, spec)
	if not ok then
		fail(label, tostring(got))
	elseif got == expected then
		pass(label)
	else
		fail(label, ("expected %s, got %s"):format(tostring(expected), tostring(got)))
	end
end

local accepted_versions = {
	{ "*", "version='*' lowers to a semver range" },
	{ "", "empty version is all versions (lazy.nvim/vim.version.range)" },
	{ ">=2.0.0", "range operators stay semver ranges" },
	{ "^1.2", "caret ranges stay semver ranges" },
	{ "~1.2", "tilde ranges stay semver ranges" },
	{ ">1.2", "greater-than ranges stay semver ranges" },
	{ "<1.2", "less-than ranges stay semver ranges" },
	{ "<=1.2", "less-than-or-equal ranges stay semver ranges" },
	{ "=1.2", "equality ranges stay semver ranges" },
	{ "v1.2.3", "v-prefixed versions stay semver ranges" },
	{ "V1.2.3", "uppercase V-prefixed versions stay semver ranges" },
	{ "1.2.3", "exact version strings stay semver ranges" },
	{ "1.2", "partial versions stay semver ranges" },
	{ "1", "partial major versions stay semver ranges" },
	{ "1.x", "wildcard minor versions stay semver ranges" },
	{ "1.2.x", "wildcard patch versions stay semver ranges" },
	{ "1.2.3-rc.1", "prerelease versions stay semver ranges" },
	{ "1.2.3+build.2", "build metadata stays a semver range" },
	{ "1.2.3-rc.1+build.2", "prerelease + build metadata stays a semver range" },
	{ "1.2.3 - 2.3.4", "hyphen ranges stay semver ranges" },
}
for _, case in ipairs(accepted_versions) do
	version_case({ version = case[1] }, "RANGE(" .. case[1] .. ")", case[2])
end

version_case({ branch = "main" }, "main", "branch lowers to a vim.pack ref")
version_case({ tag = "v1.0.0" }, "v1.0.0", "tag lowers to a vim.pack ref")
version_case({ commit = "abc123" }, "abc123", "commit lowers to a vim.pack ref")
version_case(
	{ commit = "c", tag = "t", version = "1.0.0", branch = "b" },
	"c",
	"precedence: commit > tag > version > branch"
)
version_case({ tag = "t", version = "1.0.0", branch = "b" }, "t", "precedence: tag > version > branch")
version_case({ version = "1.0.0", branch = "b" }, "RANGE(1.0.0)", "precedence: version > branch")
version_case({ version = false, branch = "b" }, "b", "version=false falls through to branch")
version_case({ version = false, tag = "t" }, "t", "version=false falls through to tag")
version_case({ version = false, commit = "c" }, "c", "version=false falls through to commit")
version_case({ tag = "t", version = "main" }, "t", "tag wins before version is parsed")
version_case({ commit = "c", version = "main" }, "c", "commit wins before version is parsed")
version_case({ version = false }, nil, "version=false without branch → vim.pack default")
version_case({}, nil, "no version fields → vim.pack default")

-- Invalid version strings must fail loudly, not become refs or truncated ranges.
local invalid_versions = {
	"main",
	"abc123",
	"1.2 || 1.3",
	">=1.2.0 <2.0.0",
	">=1.2.0<2.0.0",
	">=1.2.0\t<2.0.0",
	">= 1.0.0",
	"1.2.3 - ",
	"1.2.3 - 2.3.4 - 3.4.5",
	"1.2.3 garbage",
	"1.2.3;2.0.0",
	"1.2.3 && 2.0.0",
	">>1.2",
	"==1.2",
	"~>1.2",
	"1.2.3.4",
	"1.2.3garbage",
	"1.x.3",
	"1.2.3-",
	"1.2.3+",
	"1.2.3-rc..1",
	" ",
	"1.2.3 ",
}
for _, v in ipairs(invalid_versions) do
	local ok, err = pcall(resolve_version, { version = v })
	if ok then
		fail(("version=%q is rejected"):format(v), "resolve_version accepted it")
	elseif not tostring(err):find("semver range") then
		fail(("version=%q is rejected"):format(v), tostring(err))
	else
		pass(("version=%q is rejected"):format(v))
	end
end

local invalid_called = {}
for _, v in ipairs(invalid_versions) do
	for _, call in ipairs(range_calls) do
		if call == v then
			table.insert(invalid_called, v)
		end
	end
end
if #invalid_called == 0 then
	pass("invalid version strings never reach vim.version.range")
else
	fail("invalid version strings never reach vim.version.range", table.concat(invalid_called, ", "))
end

print("\n=== subset: known differences registry ===\n")

-- The canonical human-readable index is docs/known-differences.md; the
-- machine-readable mirror is tests/fixtures/known_differences.lua. Keep both
-- in sync. Test references are either "path: static label" (the label must
-- occur in that file) or "docs-only: reason" for delegated behavior that
-- cannot be exercised inside laze.
local known = require("tests.fixtures.known_differences")
local required_fields = {
	"id",
	"title",
	"area",
	"class",
	"notify",
	"lazy",
	"laze",
	"rationale",
	"test",
}
local allowed_classes = {
	["safe-direction"] = true,
	delegated = true,
	extension = true,
	encoding = true,
	["silent-drop"] = true,
}
local allowed_notify = { never = true, compile = true }

local kd_errors = {}
local kd_seen = {}
for _, kd in ipairs(known) do
	local label = tostring(kd.id or "<missing id>")
	for _, field in ipairs(required_fields) do
		if type(kd[field]) ~= "string" or kd[field] == "" then
			table.insert(kd_errors, ("%s: missing %s"):format(label, field))
		end
	end
	if type(kd.id) == "string" then
		if not kd.id:match("^KD%-%d%d%d$") then
			table.insert(kd_errors, ("%s: id must match KD-NNN"):format(label))
		end
		if kd_seen[kd.id] then
			table.insert(kd_errors, ("%s: duplicate id"):format(label))
		end
		kd_seen[kd.id] = true
	end
	if type(kd.class) == "string" and not allowed_classes[kd.class] then
		table.insert(kd_errors, ("%s: unknown class %q"):format(label, kd.class))
	end
	if type(kd.notify) == "string" and not allowed_notify[kd.notify] then
		table.insert(kd_errors, ("%s: unknown notify policy %q"):format(label, kd.notify))
	end
	if type(kd.test) == "string" and not kd.test:match("^docs%-only:") then
		local file, test_label = kd.test:match("^([^:]+): (.+)$")
		if not file then
			table.insert(kd_errors, ("%s: test must be 'path: label' or 'docs-only: reason'"):format(label))
		else
			local fh = io.open(file, "r")
			if not fh then
				table.insert(kd_errors, ("%s: test file %q does not exist"):format(label, file))
			else
				local contents = fh:read("*a")
				fh:close()
				if not contents:find(test_label, 1, true) then
					table.insert(kd_errors, ("%s: test label %q not found in %s"):format(label, test_label, file))
				end
			end
		end
	end
end

if #kd_errors == 0 then
	pass(("known differences: %d entries have valid fields and test references"):format(#known))
else
	fail("known differences registry is valid", table.concat(kd_errors, "; "))
end

local doc_fh = io.open("docs/known-differences.md", "r")
if not doc_fh then
	fail("known differences docs exist", "docs/known-differences.md is missing")
else
	local doc = doc_fh:read("*a")
	doc_fh:close()
	local doc_ids = {}
	for id in doc:gmatch("KD%-%d%d%d") do
		doc_ids[id] = true
	end
	local missing, extra = {}, {}
	for id in pairs(kd_seen) do
		if not doc_ids[id] then
			table.insert(missing, id)
		end
	end
	for id in pairs(doc_ids) do
		if not kd_seen[id] then
			table.insert(extra, id)
		end
	end
	table.sort(missing)
	table.sort(extra)
	local doc_errors = {}
	if #missing > 0 then
		table.insert(doc_errors, "missing from docs: " .. table.concat(missing, ", "))
	end
	if #extra > 0 then
		table.insert(doc_errors, "documented but not registered: " .. table.concat(extra, ", "))
	end
	if #doc_errors == 0 then
		pass("known differences: docs and registry IDs are in sync")
	else
		fail("known differences docs and registry IDs are in sync", table.concat(doc_errors, "; "))
	end
end

print(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end