--- test_subset.lua — verify laze's spec surface stays a lazy.nvim subset.
--- Run: luajit tests/test_subset.lua
---
--- The escape-hatch principle (see AGENTS.md): a config written for laze
--- should work in lazy.nvim with little or no changes. This test pins that
--- property as data: every field name laze consumes must be a documented
--- lazy.nvim spec field, or an explicitly justified exception.

package.path = string.format("./lua/?.lua;%s", package.path)

-- Minimal vim stub (same shape as tests/test_compile.lua)
vim = {}
vim.log = { levels = { WARN = "WARN" } }
vim.notify = function() end
vim.version = { range = function()
	return "RANGE"
end }

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
	version = "string|vim.VersionRange — passed through to vim.pack",
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
	"version: passed through to vim.pack unchanged (branch/tag/commit string or vim.version.range() object). lazy.nvim's semver strings and version=false need conversion; branch/tag/commit are lazy.nvim-only and warn — use version instead.",
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

print(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end