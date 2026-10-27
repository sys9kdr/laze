--- test_compile.lua — Standalone compile tests for laze (no Neovim required)
--- Run: luajit tests/test_compile.lua

package.path = string.format("./lua/?.lua;%s", package.path)

-- Stub vim module for non-Neovim environments
vim = {}
vim.log = { levels = { WARN = "WARN" } }
vim.notify = function() end
vim.fn = {
	expand = function(s)
		return s:gsub("^~", os.getenv("HOME") or "")
	end,
}
vim.version = { range = function(v)
	return "RANGE:" .. v
end }
vim.inspect = function(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	if type(v) == "nil" then
		return "nil"
	end
	if type(v) == "table" then
		local parts = {}
		for k, val in pairs(v) do
			table.insert(parts, string.format("%s = %s", vim.inspect(k), vim.inspect(val)))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

local compile = require("laze.compile").compile
local derive_name = require("laze.compile").derive_name
local pkg_name = require("laze.compile").pkg_name
local resolve_src = require("laze.compile").resolve_src
local normalize_keys = require("laze.compile").normalize_keys
local normalize_events = require("laze.compile").normalize_events
local resolve_version = require("laze.compile").resolve_version
local FN = require("tests.fixtures._sentinel").FN

local passed = 0
local failed = 0

local function deep_compare(got, expected, path)
	path = path or "root"

	if expected == FN then
		if type(got) ~= "function" then
			error(("  %s: expected function, got %s (%s)"):format(path, type(got), vim.inspect(got)))
		end
		return
	end

	if type(got) ~= type(expected) then
		error(
			("  %s: type mismatch \226\128\148 expected %s, got %s (%s)"):format(
				path,
				type(expected),
				type(got),
				vim.inspect(got)
			)
		)
	end

	if type(expected) == "table" then
		local seen = {}
		for k, v in pairs(expected) do
			seen[k] = true
			if got[k] == nil then
				error(("  %s[%s]: missing key in result"):format(path, vim.inspect(k)))
			end
			deep_compare(got[k], v, ("%s[%s]"):format(path, vim.inspect(k)))
		end
		for k, _ in pairs(got) do
			if seen[k] == nil then
				error(("  %s[%s]: unexpected extra key"):format(path, vim.inspect(k)))
			end
		end
	elseif type(expected) == "number" then
		if got ~= expected then
			error(("  %s: expected %s, got %s"):format(path, vim.inspect(expected), vim.inspect(got)))
		end
	elseif got ~= expected then
		error(("  %s: expected %s, got %s"):format(path, vim.inspect(expected), vim.inspect(got)))
	end
end

local function compile_fixture(name)
	local ok, fixture = pcall(require, "tests.fixtures." .. name)
	if not ok then
		return nil, ("could not load fixture \226\128\148 %s"):format(fixture)
	end
	local ok3, compiled = pcall(compile, fixture.specs, fixture.opts)
	if not ok3 then
		return nil, ("compile failed \226\128\148 %s"):format(compiled)
	end
	return compiled
end

print("=== compile tests ===\n")

local compile_fixtures = {
	"basic",
	"dev_key",
	"disabled",
	"after_deps",
	"name_override",
	"dir_source",
	"dependencies",
	"silent",
	"cond",
	"version_data",
	"unknown_fields",
	"module_trigger",
	"build_dev",
	"keys_rhs",
	"version_convert",
	"deps_dedup",
	"event_pattern",
	"keys_opts",
	"cond_enabled",
}

for _, name in ipairs(compile_fixtures) do
	local compiled = compile_fixture(name)
	if not compiled then
		print(("  \xe2\x9c\x97 %s: %s"):format(name, compiled))
		failed = failed + 1
		goto continue_compile
	end

	local ok, expected = pcall(require, "tests.snapshots." .. name)
	if not ok then
		print(("  \xe2\x9c\x97 %s: could not load snapshot \226\128\148 %s"):format(name, expected))
		failed = failed + 1
		goto continue_compile
	end

	local ok4, err = pcall(deep_compare, compiled, expected)
	if ok4 then
		print(("  \xe2\x9c\x93 %s"):format(name))
		passed = passed + 1
	else
		print(("  \xe2\x9c\x97 %s\n%s"):format(name, err))
		failed = failed + 1
	end

	::continue_compile::
end

print("\n=== derive_name tests ===\n")

local derive_cases = {
	{ "https://github.com/folke/which-key.nvim", "which-key", "GitHub URL" },
	{ "git@github.com:user/repo.nvim", "repo", "SSH URL" },
	{ "/home/user/projects/my-plugin", "my-plugin", "Local dir" },
	{ "~/dev/myplugin", "myplugin", "Tilde path" },
	{ "./local/plugin.lua", "plugin", "Relative path (.lua stripped)" },
	{ "https://github.com/user/plugin", "plugin", "URL without .nvim" },
	{ "git@github.com:user/plugin", "plugin", "SSH without .nvim" },
	{ "https://github.com/user/repo.git", "repo", ".git suffix stripped (lazy.nvim parity)" },
	{ "https://github.com/user/repo.nvim.git", "repo", ".git then .nvim stripped" },
	{ "https://github.com/user/plugin/", "plugin", "trailing slash tolerated" },
	{ "https://github.com/user/plugin.git/", "plugin", "trailing slash after .git" },
	{ "https://github.com/user/repo//", "https://github.com/user/repo/", "double trailing slash: pattern fails, raw fallback (match parity)" },
	{ "///", "//", "all-separator input falls back raw" },
	{ ":", ":", "lone colon falls back raw" },
	{ "a:b/c", "c", "colon and slash both segment separators" },
	{ "x.lua.nvim", "x", ".nvim then .lua stripped sequentially" },
	{ "x.nvim.lua", "x.nvim", "only trailing .lua stripped in one pass" },
	{ ".git", "", "whole-string .git strip empties the name" },
	{ "", "", "empty src yields empty name" },
	{ ".nvim", "", "whole-string .nvim strip empties the name" },
	{ "repo.nvim/", "repo", "trailing slash then suffix strip" },
	{ "a/b/.git", "a/b/", ".git strip leaves trailing slash: raw fallback (match parity)" },
	{ "A/B.NVIM", "B.NVIM", "suffix match is case-sensitive" },
}

for _, case in ipairs(derive_cases) do
	local src, expected, label = case[1], case[2], case[3]
	local result = derive_name(src)
	if result == expected then
		print(("  \xe2\x9c\x93 %s"):format(label))
		passed = passed + 1
	else
		print(("  \xe2\x9c\x97 %s: expected %q, got %q"):format(label, expected, result))
		failed = failed + 1
	end
end

-- Table-driven tiny unit tests for the pure compile helpers.

local function check(got, expected, label)
	local ok, err = pcall(deep_compare, got, expected)
	if ok then
		passed = passed + 1
		print(("  \xe2\x9c\x93 %s"):format(label))
	else
		failed = failed + 1
		print(("  \xe2\x9c\x97 %s: %s"):format(label, err))
	end
end

local function expect(cond, label)
	if cond then
		passed = passed + 1
		print(("  \xe2\x9c\x93 %s"):format(label))
	else
		failed = failed + 1
		print(("  \xe2\x9c\x97 %s"):format(label))
	end
end

print("\n=== pkg_name tests ===\n")

local pkg_cases = {
	{ "folke/which-key.nvim", nil, "which-key.nvim", "dotted repo keeps .nvim (vim.pack derivation)" },
	{ "user/repo.git", nil, "repo", ".git stripped" },
	{ "https://github.com/user/plugin", nil, "plugin", "https URL last segment" },
	{ "user/repo.lua", nil, "repo.lua", "vim.pack strips only .git (lua kept)" },
	{ "user/repo", nil, "repo", "plain short name" },
	{ "/abs/path/to/plugin", nil, "plugin", "absolute dir last segment" },
	{ "https://github.com/user/plugin.git", nil, "plugin", ".git stripped from https URL" },
	{ "https://github.com/user/plugin/", nil, "plugin", "trailing slash tolerated" },
	{ "https://github.com/user/plugin.git/", nil, "plugin", "slash then .git" },
	{ "https://github.com/", nil, "github.com", "host-only URL: host as name" },
	{ "user/repo", "custom", "custom", "explicit name wins" },
	{ "https://github.com/user/repo//", nil, "https://github.com/user/repo/", "double trailing slash: raw fallback (match parity)" },
	{ "//:", nil, "//:", "all-separator input falls back raw" },
	{ "user/repo.git.git", nil, "repo.git", "only one .git stripped" },
	{ "a/b/.git", nil, "a/b/", ".git strip leaves trailing slash: raw fallback (match parity)" },
	{ "p%1", nil, "p%1", "percent byte is literal (no gsub replacement semantics)" },
}

for _, case in ipairs(pkg_cases) do
	check(pkg_name(case[1], case[2]), case[3], case[4])
end

print("\n=== name derivation fuzz (vs frozen pattern oracle) ===\n")

-- last_segment() replaced string.match/gsub for speed. The old pattern
-- implementations are kept here as a frozen reference oracle: any future
-- edit to derive_name/pkg_name must stay equivalent to them, checked over
-- deterministic pseudo-random inputs each run.
local function oracle_derive(src)
	local name = src
	if name:sub(-1) == "/" then
		name = name:sub(1, -2)
	end
	if name:sub(-4) == ".git" then
		name = name:sub(1, -5)
	end
	name = name:match("([^/:]+)$") or name
	name = name:gsub("%.nvim$", "")
	name = name:gsub("%.lua$", "")
	return name
end

local function oracle_pkg(src, spec_name)
	if spec_name then
		return spec_name
	end
	local name = src
	if name:sub(-1) == "/" then
		name = name:sub(1, -2)
	end
	name = name:gsub("%.git$", "")
	return name:match("([^/:]+)$") or name
end

local rng_state = 0
local function rng()
	rng_state = (1103515245 * rng_state + 12345) % 2147483648
	return rng_state / 2147483648
end

local fuzz_alphabet = { "/", ":", ".", "g", "i", "t", "n", "v", "m", "l", "u", "a", "@", "~", "-", "%", "\0" }
local function fuzz_input()
	local len = math.floor(rng() ^ 2 * 40) -- biased short, up to 40 bytes
	local chars = {}
	for i = 1, len do
		chars[i] = fuzz_alphabet[math.floor(rng() * #fuzz_alphabet) + 1]
	end
	return table.concat(chars)
end

local fuzz_bad, fuzz_n = 0, 0
for _, seed in ipairs({ 20260824, 1, 424242 }) do
	rng_state = seed
	for _ = 1, 10000 do
		local s = fuzz_input()
		fuzz_n = fuzz_n + 1
		if derive_name(s) ~= oracle_derive(s) then
			fuzz_bad = fuzz_bad + 1
			print(("  \xe2\x9c\x97 derive mismatch on %q"):format(s))
		end
		if pkg_name(s, nil) ~= oracle_pkg(s, nil) then
			fuzz_bad = fuzz_bad + 1
			print(("  \xe2\x9c\x97 pkg mismatch on %q"):format(s))
		end
	end
end
expect(fuzz_bad == 0, ("%d fuzz inputs x2 derivations match the pattern oracle"):format(fuzz_n))

print("\n=== resolve_src tests ===\n")

local resolve_cases = {
	{ { src = "folke/which-key.nvim" }, "https://github.com/folke/which-key.nvim", "short name expanded to GitHub URL" },
	{ { src = "https://example.com/plugin.git" }, "https://example.com/plugin.git", "https URL as-is" },
	{ { src = "git@github.com:user/repo.git" }, "git@github.com:user/repo.git", "SSH URL as-is" },
	{ { src = "~/dev/plugin" }, (os.getenv("HOME") or "") .. "/dev/plugin", "tilde expanded" },
	{ { src = "./local/plugin" }, "./local/plugin", "relative path as-is" },
	{ { src = "/abs/plugin" }, "/abs/plugin", "absolute path as-is" },
	{ { dir = "~/d", src = "folke/x" }, (os.getenv("HOME") or "") .. "/d", "dir wins over src" },
	{ { url = "https://custom.com/r.git", src = "folke/x" }, "https://custom.com/r.git", "url wins over src" },
	{ { dir = "~/d", url = "https://custom.com/r.git" }, (os.getenv("HOME") or "") .. "/d", "dir wins over url" },
}

for _, case in ipairs(resolve_cases) do
	local spec = case[1]
	check(resolve_src(spec.src, spec.dir, spec.url, "x"), case[2], case[3])
end

do
	local ok, _ = pcall(resolve_src, nil, nil, nil, "x")
	expect(not ok, "no source at all raises an error")
end

print("\n=== normalize_keys tests ===\n")

local keys_cases = {
	{ nil, {}, "nil → no keys" },
	{ "a", { { lhs = "a", mode = "n" } }, "plain string → normal mode" },
	{ { "a", "b" }, { { lhs = "a", mode = "n" }, { lhs = "b", mode = "n" } }, "string array" },
	{
		{ { lhs = "<leader>x", mode = "i", rhs = "<cmd>X<CR>", desc = "d", silent = true } },
		{ { lhs = "<leader>x", mode = "i", rhs = "<cmd>X<CR>", desc = "d", silent = true } },
		"table with key options kept",
	},
	{ { { "a", "<cmd>A<CR>" } }, { { lhs = "a", mode = "n", rhs = "<cmd>A<CR>" } }, "tuple form [lhs, rhs]" },
	{ { { lhs = "b", mode = "v" } }, { { lhs = "b", mode = "v" } }, "explicit mode kept (default n)" },
	{ 42, {}, "non-table/string value dropped" },
}

for _, case in ipairs(keys_cases) do
	check(normalize_keys(case[1]), case[2], case[3])
end

print("\n=== normalize_events tests ===\n")

local events_cases = {
	{ nil, {}, "nil → no events" },
	{ "BufEnter", { { event = "BufEnter" } }, "plain string" },
	{ { "BufEnter", "InsertEnter" }, { { event = "BufEnter" }, { event = "InsertEnter" } }, "string array" },
	{
		{ { event = { "BufReadPre", "BufReadPost" }, pattern = "*.lua" } },
		{ { event = "BufReadPre", pattern = "*.lua" }, { event = "BufReadPost", pattern = "*.lua" } },
		"multi-event form with shared pattern expanded",
	},
	{
		{ { event = "BufEnter", pattern = "*.md" } },
		{ { event = "BufEnter", pattern = "*.md" } },
		"single event with pattern",
	},
	{ "BufRead", { { event = "BufReadPost" } }, "alias normalized to stored form" },
	{ "BufWrite", { { event = "BufWritePre" } }, "alias normalized to stored form" },
	{ "BufCreate", { { event = "BufAdd" } }, "alias normalized to stored form" },
}

for _, case in ipairs(events_cases) do
	check(normalize_events(case[1]), case[2], case[3])
end

print("\n=== resolve_version tests ===\n")

local version_cases = {
	{ { version = false }, nil, "false → default branch (nil)" },
	{ { version = "*" }, "RANGE:*", "'*' → vim.version.range (latest tag)" },
	{ { version = "" }, "RANGE:", "empty string → all versions (lazy.nvim/vim.version.range)" },
	{ { version = "2.1.0" }, "RANGE:2.1.0", "explicit version string is a semver range" },
	{ { version = "v1.2.3" }, "RANGE:v1.2.3", "v-prefixed version stays a semver range" },
	{ { version = "V1.2.3" }, "RANGE:V1.2.3", "uppercase V-prefixed version stays a semver range" },
	{ { version = "1" }, "RANGE:1", "partial major version stays a semver range" },
	{ { version = "1.2" }, "RANGE:1.2", "partial minor version stays a semver range" },
	{ { version = "1.x" }, "RANGE:1.x", "wildcard minor version stays a semver range" },
	{ { version = "1.2.x" }, "RANGE:1.2.x", "wildcard patch version stays a semver range" },
	{ { version = "^1.2.3" }, "RANGE:^1.2.3", "caret range stays a semver range" },
	{ { version = "~1.2.3" }, "RANGE:~1.2.3", "tilde range stays a semver range" },
	{ { version = ">1.2.3" }, "RANGE:>1.2.3", "greater-than range stays a semver range" },
	{ { version = ">=2.0.0" }, "RANGE:>=2.0.0", "range operator stays a semver range" },
	{ { version = "<1.2.3" }, "RANGE:<1.2.3", "less-than range stays a semver range" },
	{ { version = "<=1.2.3" }, "RANGE:<=1.2.3", "less-than-or-equal range stays a semver range" },
	{ { version = "=1.2.3" }, "RANGE:=1.2.3", "explicit equality range stays a semver range" },
	{ { version = "1.2.3-rc.1" }, "RANGE:1.2.3-rc.1", "prerelease version stays a semver range" },
	{ { version = "1.2.3+build.2" }, "RANGE:1.2.3+build.2", "build metadata stays a semver range" },
	{
		{ version = "1.2.3-rc.1+build.2" },
		"RANGE:1.2.3-rc.1+build.2",
		"prerelease + build metadata stays a semver range",
	},
	{ { version = "1.2.3 - 2.3.4" }, "RANGE:1.2.3 - 2.3.4", "hyphen range stays a semver range" },
	{
		{ commit = "abc123", tag = "v1", version = "1.0.0", branch = "main" },
		"abc123",
		"commit > tag > version > branch",
	},
	{ { tag = "v1", version = "1.0.0", branch = "main" }, "v1", "tag > version > branch" },
	{ { version = "1.0.0", branch = "main" }, "RANGE:1.0.0", "version > branch" },
	{ { version = false, branch = "main" }, "main", "false skips version, uses branch" },
	{ { version = false, tag = "v1" }, "v1", "false skips version, uses tag" },
	{ { version = false, commit = "abc123" }, "abc123", "false skips version, uses commit" },
	{ { tag = "v1", version = "main" }, "v1", "tag wins before version is parsed" },
	{ { commit = "abc123", version = "main" }, "abc123", "commit wins before version is parsed" },
	{ { branch = "main" }, "main", "branch alone" },
	{ {}, nil, "nothing → default branch" },
}

for _, case in ipairs(version_cases) do
	check(resolve_version(case[1]), case[2], case[3])
end

-- These must fail before reaching vim.version.range; otherwise vim.version.range
-- would silently narrow or misparse them.
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
	expect(not ok and tostring(err):find("semver range") ~= nil, ("invalid version %q is rejected"):format(v))
end

do
	local old_range = vim.version.range
	local sentinel = {}
	local calls = 0
	vim.version.range = function()
		calls = calls + 1
		return sentinel
	end
	local ok, c = pcall(compile, { { "folke/versioned.nvim", name = "versioned", version = ">=1.0.0" } })
	vim.version.range = old_range
	expect(ok, "compile accepts a version-only range")
	if ok then
		expect(c.pack[1].version == sentinel, "compile lowers version to the vim.version.range object")
		expect(calls == 1, "compile parses each version range once")
	end
end

do
	local c = compile({ { "folke/false-branch.nvim", name = "false-branch", version = false, branch = "develop" } })
	expect(c.pack[1].version == "develop", "compile keeps branch when version=false")
end

do
	local c = compile({ { "folke/tag-wins.nvim", name = "tag-wins", tag = "v1", version = "main" } })
	expect(c.pack[1].version == "v1", "compile does not parse a version overridden by tag")
end

do
	local ok, err = pcall(compile, { { dir = "/tmp/laze-dir", name = "local", version = "main" } })
	expect(not ok and tostring(err):find("semver range") ~= nil, "dir plugin with invalid version is rejected")
	local ok2, c = pcall(compile, { { dir = "/tmp/laze-dir", name = "local", version = ">=1.0.0" } })
	expect(ok2 and #c.pack == 0, "dir plugin with valid version compiles with no pack entry")
end

print("\n=== compile detail tests ===\n")

do
	local c = compile({ { "folke/which-key.nvim" } })
	local e = c.registry["which-key"]
	expect(e.pkg == "which-key.nvim", "dotted repo: registry pkg keeps .nvim")
	expect(c.pack[1].name == "which-key.nvim", "dotted repo: pack entry name matches vim.pack derivation")
	expect(c.pack[1].src == "https://github.com/folke/which-key.nvim", "dotted repo: src expanded")
	expect(e.is_dep == false and e.has_route == false, "dotted repo: eager, not a dep")
end

do
	local c = compile({
		{ "folke/dep.nvim", name = "dep" },
		{ "folke/parent.nvim", name = "parent", dependencies = { "dep" } },
	})
	expect(#c.pack == 2, "dependencies: top-level spec referenced by name, not re-registered")
	expect(c.registry["parent"].after[1] == "dep", "dependencies: wired as after")
	expect(c.registry["dep"].is_dep == true, "dependencies: dep is never eager")
	expect(c.registry["parent"].is_dep == false, "dependencies: parent itself is not a dep")
end

do
	local c = compile({
		{ "folke/parent.nvim", name = "parent", dependencies = { { "folke/inline.nvim" } } },
	})
	expect(#c.pack == 2, "dependencies: inline full spec registered once")
	expect(c.registry["inline"].is_dep == true, "dependencies: inline dep is_dep")
	expect(c.registry["parent"].after[1] == "inline", "dependencies: inline dep wired as after")
end

do
	local c = compile({ { dir = "/tmp/plugin", name = "localp" } })
	expect(#c.pack == 0, "dir plugin: no pack entry")
	expect(c.registry["localp"].pkg == nil, "dir plugin: no pkg")
	expect(c.registry["localp"].dir == "/tmp/plugin", "dir plugin: dir kept")
end

do
	local c = compile({ { "folke/x.nvim", name = "x", priority = 90 } })
	expect(c.registry["x"].priority == 90, "priority: explicit number kept")
	local d = compile({ { "folke/y.nvim", name = "y" } })
	expect(d.registry["y"].priority == 50, "priority: default 50")
end

do
	local c = compile({
		{ "folke/x.nvim", name = "x", module = { "x.mod", "x.other" } },
	})
	expect(c.registry["x"].has_route == true, "module trigger: has_route")
	expect(c.routes.modules["x.mod"][1] == "x", "module trigger: routed")
end

do
	local c = compile({
		{ "folke/x.nvim", name = "x", event = "InsertEnter" },
	})
	expect(c.registry["x"].has_route == true, "event trigger: has_route")
end

print("\n=== trigger validation tests ===\n")

local rejection_cases = {
	{
		{ "folke/x.nvim", name = "x", keys = function()
			return {}
		end },
		"function triggers are not supported",
		"keys function rejected (never silently eager)",
	},
	{ { "folke/x.nvim", name = "x", event = 42 }, "event must be a string or array", "numeric event rejected" },
	{ { "folke/x.nvim", name = "x", event = function() end }, "function triggers are not supported", "event function rejected" },
	{ { "folke/x.nvim", name = "x", ft = { "lua", 42 } }, "ft[2] must be a string", "non-string inside ft rejected" },
	{ { "folke/x.nvim", name = "x", cmd = { {} } }, "cmd[1] must be a string", "table inside cmd rejected" },
	{ { "folke/x.nvim", name = "x", ft = false }, "ft must be a string or array", "boolean ft rejected" },
	{ { "folke/x.nvim", name = "x", keys = { {} } }, "non-empty lhs", "keys entry without lhs rejected" },
	{ { "folke/x.nvim", name = "x", keys = { { lhs = "" } } }, "non-empty lhs", "empty lhs rejected" },
	{ { "folke/x.nvim", name = "x", keys = { { lhs = "a", mode = 42 } } }, "mode must be a string or string[]", "numeric mode rejected" },
	{ { "folke/x.nvim", name = "x", event = { { event = 42 } } }, "must have event = string", "numeric event in table rejected" },
	{ { "folke/x.nvim", name = "x", event = { { event = { "A", 42 } } } }, "must have event = string", "non-string in event array rejected" },
	{ { "folke/x.nvim", name = "x", event = { { event = "BufEnter", pattern = 42 } } }, "pattern must be a string", "numeric pattern rejected" },
	{ { "folke/x.nvim", name = "x", event = { "ok", {} } }, "event[2] must have event = string", "bare table in event rejected" },
	{ { "folke/x.nvim", name = "x", config = true }, "config = true is not supported", "config=true rejected" },
	{ { "folke/x.nvim", name = "x", config = 42 }, "config must be a function", "non-function config rejected" },
	{ { "folke/x.nvim", name = "x", init = 42 }, "init must be a function", "non-function init rejected" },
	{ { "folke/x.nvim", name = "x", cond = "yes" }, "cond must be a function or boolean", "string cond rejected" },
	{ { "folke/x.nvim", name = "x", enabled = "yes" }, "enabled must be a function or boolean", "string enabled rejected" },
	{ { "folke/x.nvim", name = "x", after = "dep" }, "after must be an array", "string after rejected" },
	{ { "folke/x.nvim", name = "x", after = { 42 } }, "after[1] must be a non-empty plugin id", "numeric after element rejected" },
	{ { "folke/x.nvim", name = "x", after = { "" } }, "after[1] must be a non-empty plugin id", "empty after element rejected" },
	{ { "folke/x.nvim", name = "x", build = 42 }, "build must be a string, function, or false", "numeric build rejected" },
	{ { "folke/x.nvim", name = "x", build = true }, "build must be a string, function, or false", "boolean build rejected" },
	{ { "folke/x.nvim", name = "x", module = 42 }, "module must be a string, array, or false", "numeric module rejected" },
	{ { "folke/x.nvim", name = "x", module = { "a", 42 } }, "module[2] must be a non-empty string", "non-string module element rejected" },
	{ { "folke/x.nvim", name = "x", module = {} }, "module must not be an empty array", "empty module array rejected" },
	{ { "folke/x.nvim", name = "x", version = 42 }, "version must be a string", "numeric version rejected" },
	{ { "folke/x.nvim", name = "x", version = {} }, "version must be a string", "table version rejected" },
	{ { "folke/x.nvim", name = "x", version = "main" }, "not a supported semver range", "git ref in version rejected" },
	{ { "folke/x.nvim", name = "x", version = "abc123" }, "not a supported semver range", "commit hash in version rejected" },
	{ { "folke/x.nvim", name = "x", version = "1.2 || 1.3" }, "not a supported semver range", "multi-range version rejected" },
	{ { "folke/x.nvim", name = "x", branch = 42 }, "branch must be a non-empty string", "numeric branch rejected" },
	{ { "folke/x.nvim", name = "x", tag = "" }, "tag must be a non-empty string", "empty tag rejected" },
	{ { "folke/x.nvim", name = "x", commit = {} }, "commit must be a non-empty string", "table commit rejected" },
	{ { "folke/x.nvim", name = "x", priority = "high" }, "priority must be a number", "string priority rejected" },
	{ { "folke/x.nvim", name = "x", ft = "" }, "must not be empty", "empty ft rejected" },
	{ { "folke/x.nvim", name = "x", cmd = { "" } }, "must not be empty", "empty cmd element rejected" },
	{ { "folke/x.nvim", name = "x", event = "" }, "must not be empty", "empty event rejected" },
	{ { "folke/x.nvim", name = "x", keys = "" }, "must not be empty", "empty keys string rejected" },
	{ { "folke/x.nvim", name = "x", keys = { "" } }, "must not be empty", "empty keys element rejected" },
	{ { "folke/x.nvim", name = "x", event = { { event = "" } } }, "event must not be empty", "empty event in entry rejected" },
	{ { "folke/x.nvim", name = "x", event = { { event = { "A", "" } } } }, "event must not be empty", "empty event in array rejected" },
	{ { "folke/x.nvim", name = "" }, "name must be a non-empty string", "empty name rejected" },
	{ { "folke/x.nvim", name = "x", dir = "" }, "dir must be a non-empty string", "empty dir rejected" },
	{ { "folke/x.nvim", name = "x", url = "" }, "url must be a non-empty string", "empty url rejected" },
	{ { "", name = "x" }, "[1]/src must be a non-empty string", "empty src rejected" },
	{ { 42, name = "x" }, "[1]/src must be a non-empty string", "numeric src rejected" },
	{ { "folke/x.nvim", name = "x", keys = { 42 } }, "keys[1] must be a string", "numeric keys element rejected" },
	{ { "folke/x.nvim", name = "x", keys = { { lhs = 42 } } }, "non-empty lhs", "numeric lhs rejected" },
}

for _, case in ipairs(rejection_cases) do
	local ok, err = pcall(compile, { case[1] })
	expect(not ok and err and err:find(case[2], 1, true) ~= nil, case[3])
end

do
	local c = compile({ { "folke/x.nvim", name = "x", keys = { { "<leader>x", "<cmd>X<CR>" } } } })
	expect(c.registry["x"].has_route == true, "tuple keys entry still accepted")
	expect(c.routes.keys["<leader>x"].rhs == "<cmd>X<CR>", "tuple keys rhs routed")
end

do
	local c = compile({ { "folke/x.nvim", name = "x", keys = { { lhs = "<leader>m", mode = { "n", "v" } } } } })
	expect(c.routes.keys["<leader>m"].mode[1] == "n" and c.routes.keys["<leader>m"].mode[2] == "v", "multi-mode keys accepted")
end

-- Dependency expansion: purity, nested drop warning, shape validation
do
	local specs = {
		{ "folke/parent.nvim", name = "parent", dependencies = { "dep" } },
		{ "folke/dep.nvim", name = "dep" },
	}
	local c = compile(specs)
	expect(specs[1].after == nil, "compile does not mutate input specs (no after injection)")
	expect(c.registry["parent"].after[1] == "dep", "dependency-derived after wired")
	expect(c.registry["parent"].is_dep == false and c.registry["dep"].is_dep == true, "dep marked is_dep")
	local c2 = compile(specs)
	expect(c2.registry["parent"].after[1] == "dep" and specs[1].after == nil, "re-compile deterministic and still pure")
end

do
	local specs = {
		{
			"folke/merge.nvim",
			name = "merge",
			dependencies = { "dep" },
			after = { "explicit", "dep" }, -- same dep named both ways: deduped
		},
		{ "folke/dep.nvim", name = "dep" },
		{ "folke/explicit.nvim", name = "explicit" },
	}
	local c = compile(specs)
	local after = c.registry["merge"].after
	expect(
		after[1] == "explicit" and after[2] == "dep" and #after == 2,
		"explicit after first, dependency-derived merged and deduped"
	)
end

do
	local msgs = {}
	vim.notify = function(msg, _)
		table.insert(msgs, msg)
	end
	local c = compile({
		{
			"folke/parent.nvim",
			name = "nested-parent",
			dependencies = { { "folke/child.nvim", name = "nested-child", dependencies = { "grand" } } },
		},
	})
	vim.notify = function() end
	local found = false
	for _, m in ipairs(msgs) do
		if m:find("nested", 1, true) then
			found = true
		end
	end
	expect(found, "nested dependencies on inline dep specs warn")
	expect(c.registry["nested-child"].is_dep == true and c.registry["nested-parent"] ~= nil, "inline dep itself still registered")
end

do
	local cases = {
		{ { "folke/x.nvim", name = "x", dependencies = 42 }, "dependencies must be a string", "numeric dependencies rejected" },
		{ { "folke/x.nvim", name = "x", dependencies = { "a", 42 } }, "dependencies[2] must be a string", "non-string element in dependencies rejected" },
	}
	for _, case in ipairs(cases) do
		local ok, err = pcall(compile, { case[1] })
		expect(not ok and err and err:find(case[2], 1, true) ~= nil, case[3])
	end
end

do
	local c = compile({ { "folke/x.nvim", name = "x", build = false } })
	expect(c.registry["x"].build == nil, "build = false accepted as no-build (lazy.nvim semantics)")
	local ok, err = pcall(compile, { { "folke/x.nvim", name = "x", build = { "make", "make test" } } })
	expect(not ok and err and err:find("list form", 1, true) ~= nil, "build list form rejected with a clear message")
end

do
	local ok, err = pcall(compile, {
		{ "folke/a.nvim", name = "dup-id" },
		{ "folke/b.nvim", name = "dup-id" },
	})
	expect(not ok and err and err:find("duplicate name", 1, true) ~= nil, "duplicate id rejected (was a silent overwrite)")
	local ok2, err2 = pcall(compile, {})
	expect(not ok2 and err2 and err2:find("non-empty array", 1, true) ~= nil, "empty spec array rejected")
	local ok3, err3 = pcall(compile)
	expect(not ok3 and err3 and err3:find("non-empty array", 1, true) ~= nil, "nil specs rejected")
	local s1 = { "folke/a.nvim", name = "sparse-a" }
	local sparse = { [1] = s1, [3] = { "folke/b.nvim", name = "sparse-b" } }
	local ok4, err4 = pcall(compile, sparse)
	expect(not ok4 and err4 and err4:find("must not be sparse", 1, true) ~= nil, "sparse spec array rejected (ipairs would drop [3])")
	local ok5, err5 = pcall(compile, { "folke/a.nvim" })
	expect(not ok5 and err5 and err5:find("must be a spec table", 1, true) ~= nil, "non-table element rejected")
	local ok6, err6 = pcall(compile, { { "folke/a.nvim", name = "dup-name", build = 42 } })
	expect(not ok6 and err6 and err6:find("build must be a string", 1, true) ~= nil, "invalid build still caught before duplicate check")
end

do
	local msgs = {}
	vim.notify = function(msg, _)
		table.insert(msgs, msg)
	end
	compile({
		{
			"folke/x.nvim",
			name = "x-unsup",
			main = "m",
			opts = { a = 1 },
			submodules = false,
			optional = true,
			import = "lua/plugins",
			lazy = true,
			specs = {},
		},
	})
	vim.notify = function() end
	for _, field in ipairs({ "submodules", "optional", "import", "lazy", "specs" }) do
		local found = false
		for _, m in ipairs(msgs) do
			if m:find("'" .. field .. "'", 1, true) then
				found = true
			end
		end
		expect(found, "unsupported field '" .. field .. "' warns")
	end
	for _, field in ipairs({ "main", "opts" }) do
		local found = false
		for _, m in ipairs(msgs) do
			if m:find("'" .. field .. "'", 1, true) then
				found = true
			end
		end
		expect(not found, "supported field '" .. field .. "' does not warn")
	end
	expect(#msgs == 5, "exactly one warning per unsupported field (got " .. #msgs .. ")")
end

do
	local c = compile({ { "folke/x.nvim", name = "devp", dev_path = "~/custom/devp" } })
	expect(not c.registry["devp"].src:find("^~", 1, true) and c.registry["devp"].src ~= "", "dev_path with ~ is expanded")
	local c2 = compile({ { "folke/x.nvim", name = "devp2", dev_path = "/abs/devp2" } })
	expect(c2.registry["devp2"].src == "/abs/devp2", "dev_path absolute stays verbatim")
	local c3 = compile({ { "folke/x.nvim", name = "dev3", dev = "/abs/dev3" } })
	expect(c3.registry["dev3"].src == "/abs/dev3", "dev = '/abs' string redirects src (was inert)")
	local c4 = compile({ { "folke/x.nvim", name = "dev4", dev = "rel/dev4" } })
	expect(c4.registry["dev4"].src == "rel/dev4", "dev = 'rel' string redirects src")
	local c5 = compile({ { "folke/x.nvim", name = "dev5", dev = "~/dev5" } })
	expect(not c5.registry["dev5"].src:find("^~", 1, true), "dev = '~/...' string expands")
end

do
	local c = compile({
		{
			"folke/p.nvim",
			name = "p-dir",
			dependencies = { { dir = "/tmp/depdir" } },
		},
	})
	expect(c.registry["depdir"] ~= nil and c.registry["p-dir"].after[1] == "depdir", "inline dir-only dep resolves by dir name")
	local c2 = compile({
		{ "folke/p2.nvim", name = "p-dup", dependencies = { "d1", "d1" } },
		{ "folke/d1.nvim", name = "d1" },
	})
	expect(#c2.registry["p-dup"].after == 1, "same dep listed twice in one array wired once")
end

print(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end
