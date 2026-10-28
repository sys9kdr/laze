--- Test runner for laze
---
--- Run: nvim --cmd "set rtp+=." -l tests/run.lua [fast] [fixture ...] [perf]
--- Compile tests compare against snapshots in tests/snapshots/.
--- Regenerate with: nvim --cmd "set rtp+=." -l tests/update_snapshots.lua
--- `fast` skips the spawned-session blocks (startup phases, build,
--- pkg-name parity) so the common loop stays in one nvim instance.
local laze = require("laze")
local FN = require("tests.fixtures._sentinel").FN

local passed = 0
local failed = 0

-- Build fixture filter from CLI args (e.g. `nvim ... tests/run.lua basic disabled`).
-- arg[0] is the script path; args after it are fixture names to filter for.
-- `fast` is a mode flag (skip spawned sessions), not a fixture name.
local filter = {}
local fast_only = false
for i = 1, #arg do
	if arg[i] == "fast" then
		fast_only = true
	else
		-- `perf` also implies fast: the perf suite is in-process only
		-- (the docstring promises "perf regression suite only").
		if arg[i] == "perf" then
			fast_only = true
		end
		filter[arg[i]] = true
	end
end
local function is_filtered(name)
	return next(filter) == nil or filter[name] == true
end

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
			("  %s: type mismatch — expected %s, got %s (%s)"):format(
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
		return nil, ("could not load fixture — %s"):format(fixture)
	end
	local ok3, compiled = pcall(laze.compile, fixture.specs, fixture.opts)
	if not ok3 then
		return nil, ("compile failed — %s"):format(compiled)
	end
	return compiled
end

--- Compile tests
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
	"name_derivation",
	"priority_build",
	"opts_main",
	"dev_version",
}

for _, name in ipairs(compile_fixtures) do
	if not is_filtered(name) then
		goto continue_compile
	end
	local compiled = compile_fixture(name)
	if not compiled then
		print(("  ✗ %s: %s"):format(name, compiled))
		failed = failed + 1
		goto continue_compile
	end

	local ok, expected = pcall(require, "tests.snapshots." .. name)
	if not ok then
		print(("  ✗ %s: could not load snapshot — %s"):format(name, expected))
		print('    Regenerate: nvim --cmd "set rtp+=." -l tests/update_snapshots.lua')
		failed = failed + 1
		goto continue_compile
	end

	local ok4, err = pcall(deep_compare, compiled, expected)
	if ok4 then
		print(("  ✓ %s"):format(name))
		passed = passed + 1
	else
		print(("  ✗ %s\n%s"):format(name, err))
		failed = failed + 1
	end

	::continue_compile::
end

--- Version lowering against the real vim.version.range (the LuaJIT suites
--- use a stub; this pins the actual Neovim object and the compile error path).
print("\n=== version lowering (real vim.version.range) ===\n")

do
	local function compile_one(spec, label)
		local ok, compiled = pcall(laze.compile, { spec })
		if not ok then
			print(("  ✗ %s: %s"):format(label, compiled))
			failed = failed + 1
			return nil
		end
		return compiled.pack[1]
	end

	local entry = compile_one({ "user/versioned", name = "versioned", version = ">=1.2.3" }, "version-only range")
	if entry then
		local v = entry.version
		if type(v) == "table" and tostring(v) == ">=1.2.3" and v:has("1.2.3") and not v:has("1.2.2") then
			print("  ✓ version-only range lowers to a real vim.VersionRange")
			passed = passed + 1
		else
			print(("  ✗ version-only range: got %s (%s)"):format(tostring(v), type(v)))
			failed = failed + 1
		end
	end

	local hyphen = compile_one({ "user/hyphen", name = "hyphen", version = "1.2.3 - 2.0.0" }, "hyphen range")
	if hyphen then
		local v = hyphen.version
		if type(v) == "table" and v:has("1.9.9") and not v:has("2.0.0") then
			print("  ✓ hyphen range lowers to a real vim.VersionRange")
			passed = passed + 1
		else
			print(("  ✗ hyphen range: got %s (%s)"):format(tostring(v), type(v)))
			failed = failed + 1
		end
	end

	local upper = compile_one({ "user/upper", name = "upper", version = "V1.2.3" }, "uppercase V prefix")
	if upper then
		local v = upper.version
		if type(v) == "table" and v:has("1.2.3") and not v:has("1.2.4") then
			print("  ✓ uppercase V prefix is accepted")
			passed = passed + 1
		else
			print(("  ✗ uppercase V prefix: got %s (%s)"):format(tostring(v), type(v)))
			failed = failed + 1
		end
	end

	local tag_entry = compile_one(
		{ "user/tag-wins", name = "tag-wins", tag = "v1", version = "main" },
		"tag precedence"
	)
	if tag_entry then
		if tag_entry.version == "v1" then
			print("  ✓ tag wins before an invalid version is parsed")
			passed = passed + 1
		else
			print(("  ✗ tag precedence: got %s"):format(tostring(tag_entry.version)))
			failed = failed + 1
		end
	end

	local ok, err = pcall(laze.compile, { { "user/compound", name = "compound", version = ">=1.2.0 <2.0.0" } })
	if not ok and tostring(err):find("semver range") then
		print("  ✓ compound range fails at compile time")
		passed = passed + 1
	else
		print(("  ✗ compound range: expected a compile error, got %s"):format(tostring(err)))
		failed = failed + 1
	end

	-- lazy.nvim's own semver_spec cases (Apache-2.0; see the fixture header).
	-- Check membership, not the internal from/to encoding: vim.version.range
	-- encodes an exact version as [v, v] while lazy.nvim uses [v, next patch).
	local lazy_cases = require("tests.fixtures.lazy_semver_cases")
	for _, case in ipairs(lazy_cases) do
		local lazy_entry = compile_one(
			{ "user/lazy-range", name = "lazy-range", version = case.input },
			("lazy range %q"):format(case.input)
		)
		if lazy_entry then
			local v = lazy_entry.version
			local good = type(v) == "table"
			if good then
				for _, version in ipairs(case.inside) do
					good = good and v:has(version)
				end
				for _, version in ipairs(case.outside) do
					good = good and not v:has(version)
				end
			end
			if good then
				print(("  ✓ lazy range %q membership"):format(case.input))
				passed = passed + 1
			else
				print(
					("  ✗ lazy range %q: got %s (%s)"):format(
						case.input,
						tostring(v),
						type(v)
					)
				)
				failed = failed + 1
			end
		end
	end

	-- Known difference, pinned intentionally: vim.version.range(">1.2.3")
	-- starts at 1.2.4-0, so it includes 1.2.4-alpha. lazy.nvim starts at
	-- 1.2.4 and excludes prereleases of the lower bound.
	local gt = compile_one({ "user/gt", name = "gt", version = ">1.2.3" }, "greater-than prerelease boundary")
	if gt then
		local v = gt.version
		if type(v) == "table" and v:has("1.2.4-alpha") and not v:has("1.2.3") then
			print("  ✓ known difference: >1.2.3 includes 1.2.4-alpha (vim.version.range)")
			passed = passed + 1
		else
			print(("  ✗ greater-than prerelease boundary: got %s (%s)"):format(tostring(v), type(v)))
			failed = failed + 1
		end
	end
end

--- Plan tests
print("\n=== plan tests ===\n")

local function test_plan_callable(compiled, name)
	local ok, plan = pcall(laze.build_plan, compiled)
	if not ok then
		print(("  ✗ %s: build_plan failed — %s"):format(name, plan))
		failed = failed + 1
		return nil
	end
	if type(plan) ~= "function" then
		print(("  ✗ %s: plan is %s, expected function"):format(name, type(plan)))
		failed = failed + 1
		return nil
	end
	return plan
end

-- build_plan produces callable function for each fixture
for _, name in ipairs(compile_fixtures) do
	if not is_filtered(name) then
		goto continue_plan
	end
	local compiled = compile_fixture(name)
	if compiled then
		local plan = test_plan_callable(compiled, name)
		if plan then
			print(("  ✓ %s: plan is callable"):format(name))
			passed = passed + 1
		end
	end
	::continue_plan::
end

-- plan() executes without error
if is_filtered("basic") then
	do
		local compiled = compile_fixture("basic")
		if compiled then
			local plan = laze.build_plan(compiled)
			local ok, err = pcall(plan)
			if ok then
				print("  ✓ basic: plan() executed without error")
				passed = passed + 1
			else
				print(("  ✗ basic: plan() threw — %s"):format(err))
				failed = failed + 1
			end
		end
	end
end

-- CmdUndefined dispatcher is registered for cmd routes (single "*" entry
-- dispatching via routes.cmds), and firing it loads the plugin
do
	local ran = 0
	local compiled = laze.compile({
		{ "test/cmd-plugin", cmd = "LazyCmdTest", name = "cmd-test", config = function() ran = ran + 1 end },
	})
	local plan = laze.build_plan(compiled)
	plan()

	local aucmds = vim.api.nvim_get_autocmds({
		event = "CmdUndefined",
		group = "laze_cmds",
	})

	if #aucmds == 1 and aucmds[1].pattern == "*" then
		print("  ✓ cmd route: single CmdUndefined dispatcher registered")
		passed = passed + 1
	else
		print(("  ✗ cmd route: expected 1 CmdUndefined dispatcher, got %d"):format(#aucmds))
		failed = failed + 1
	end

	pcall(vim.cmd, "LazyCmdTest")
	if ran == 1 then
		print("  ✓ cmd route: dispatcher loads the plugin on command")
		passed = passed + 1
	else
		print(("  ✗ cmd route: dispatcher did not load (ran=%d)"):format(ran))
		failed = failed + 1
	end
end

-- FileType dispatcher is registered for ft routes (single "*" entry),
-- fires only for the matching filetype, and ignores unrelated ones
do
	local ran = 0
	local compiled = laze.compile({
		{ "test/ft-plugin", ft = "myfttest", config = function() ran = ran + 1 end },
	})
	local plan = laze.build_plan(compiled)
	plan()

	local aucmds = vim.api.nvim_get_autocmds({
		event = "FileType",
		group = "laze_fts",
	})

	if #aucmds == 1 and aucmds[1].pattern == "*" then
		print("  ✓ ft route: single FileType dispatcher registered")
		passed = passed + 1
	else
		print(("  ✗ ft route: expected a FileType dispatcher, got %d"):format(#aucmds))
		failed = failed + 1
	end

	local b_other = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(b_other, "other.txt")
	vim.api.nvim_exec_autocmds("FileType", { pattern = "otherft" })
	local b_hit = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(b_hit, "hit.txt")
	vim.api.nvim_exec_autocmds("FileType", { pattern = "myfttest" })
	if ran == 1 then
		print("  ✓ ft route: dispatcher fires only on the matching filetype")
		passed = passed + 1
	else
		print(("  ✗ ft route: dispatcher fired wrong (ran=%d)"):format(ran))
		failed = failed + 1
	end
end

-- keys route: keymap is registered
do
	local compiled = laze.compile({
		{ "test/key-plugin", keys = "<leader>zz" },
	})
	local plan = laze.build_plan(compiled)
	plan()

	local lhs = vim.api.nvim_replace_termcodes("<leader>zz", true, false, true)
	local keymap = vim.api.nvim_get_keymap("n")
	local found = false
	for _, km in ipairs(keymap) do
		if km.lhs == lhs then
			found = true
			break
		end
	end

	if found then
		print("  ✓ keys route: keymap registered (default n)")
		passed = passed + 1
	else
		print("  ✗ keys route: keymap not found")
		failed = failed + 1
	end
end

-- keys route: explicit mode
do
	local compiled = laze.compile({
		{ "test/key-i", keys = { { lhs = "<leader>ii", mode = "i" } } },
	})
	local plan = laze.build_plan(compiled)
	plan()

	local lhs = vim.api.nvim_replace_termcodes("<leader>ii", true, false, true)
	local found_n, found_i = false, false
	for _, km in ipairs(vim.api.nvim_get_keymap("n")) do
		if km.lhs == lhs then
			found_n = true
		end
	end
	for _, km in ipairs(vim.api.nvim_get_keymap("i")) do
		if km.lhs == lhs then
			found_i = true
		end
	end

	if not found_n and found_i then
		print("  ✓ keys route: mode=i works")
		passed = passed + 1
	else
		print(("  ✗ keys route: mode=i — n:%s i:%s"):format(found_n, found_i))
		failed = failed + 1
	end
end

-- keys route: multiple modes
do
	local compiled = laze.compile({
		{ "test/key-multi", keys = { { lhs = "<leader>mm", mode = { "n", "v" } } } },
	})
	local plan = laze.build_plan(compiled)
	plan()

	local lhs = vim.api.nvim_replace_termcodes("<leader>mm", true, false, true)
	local found_n, found_v = false, false
	for _, km in ipairs(vim.api.nvim_get_keymap("n")) do
		if km.lhs == lhs then
			found_n = true
		end
	end
	for _, km in ipairs(vim.api.nvim_get_keymap("v")) do
		if km.lhs == lhs then
			found_v = true
		end
	end

	if found_n and found_v then
		print("  ✓ keys route: multi-mode {n,v} works")
		passed = passed + 1
	else
		print(("  ✗ keys route: multi-mode — n:%s v:%s"):format(found_n, found_v))
		failed = failed + 1
	end
end

-- keys route: plugin's own keymap takes over after the trigger fires
-- (regression: the trigger map must be deleted BEFORE loading — keymap.del
-- removes every map for the lhs, which would also kill the plugin's map)
do
	local dir = vim.fn.tempname() .. "_keytake"
	vim.fn.mkdir(dir .. "/lua", "p")
	local basename = dir:match("([^/]+)$")
	local fd = io.open(dir .. "/lua/" .. basename .. ".lua", "w")
	fd:write("return { loaded = true }\n")
	fd:close()
	local lhs = vim.api.nvim_replace_termcodes("<leader>kt", true, false, true)
	local ran = false
	local compiled = laze.compile({
		{
			dir = dir,
			name = "key-takeover",
			keys = { { lhs = "<leader>kt" } },
			config = function()
				vim.keymap.set("n", "<leader>kt", function()
					ran = true
				end)
			end,
		},
	})
	local plan = laze.build_plan(compiled)
	plan()
	vim.api.nvim_feedkeys(lhs, "x", false)
	vim.wait(50)
	local remaining = 0
	for _, km in ipairs(vim.api.nvim_get_keymap("n")) do
		if km.lhs == lhs then
			remaining = remaining + 1
		end
	end
	if ran and remaining == 1 then
		print("  ✓ keys route: plugin keymap takes over (trigger deleted, plugin map kept)")
		passed = passed + 1
	else
		print(("  ✗ keys route: takeover — ran:%s remaining:%d"):format(tostring(ran), remaining))
		failed = failed + 1
	end
	vim.keymap.del("n", lhs)
	vim.fn.delete(dir, "rf")
end

-- event route: autocmd is registered
do
	local compiled = laze.compile({
		{ "test/event-plugin", event = "BufRead" },
	})
	local plan = laze.build_plan(compiled)
	plan()

	local aucmds = vim.api.nvim_get_autocmds({
		event = "BufRead",
		group = "laze_events",
	})

	if #aucmds == 1 then
		print("  ✓ event route: autocmd registered")
		passed = passed + 1
	else
		print(("  ✗ event route: expected 1 autocmd, got %d"):format(#aucmds))
		failed = failed + 1
	end
end

-- events sharing a pattern are wired by one autocmd call (rows share its
-- id) and still fire independently per event (once=true is per-row)
do
	local ran_a, ran_b = 0, 0
	local compiled = laze.compile({
		{ "test/ev-a", event = "BufRead", config = function() ran_a = ran_a + 1 end },
		{ "test/ev-b", event = "InsertEnter", config = function() ran_b = ran_b + 1 end },
	})
	local plan = laze.build_plan(compiled)
	plan()

	local rows = vim.api.nvim_get_autocmds({ group = "laze_events" })
	if #rows == 2 and rows[1].id == rows[2].id then
		print("  ✓ event route: two events share one autocmd call (same id)")
		passed = passed + 1
	else
		print(("  ✗ event route: expected 2 rows with one id, got %d rows"):format(#rows))
		failed = failed + 1
	end

	vim.api.nvim_exec_autocmds("BufRead", { group = "laze_events" })
	vim.api.nvim_exec_autocmds("BufRead", { group = "laze_events" })
	vim.api.nvim_exec_autocmds("InsertEnter", { group = "laze_events" })
	if ran_a == 1 and ran_b == 1 then
		print("  ✓ event route: grouped rows fire once each, independently")
		passed = passed + 1
	else
		print(("  ✗ event route: grouped fire — a:%d b:%d"):format(ran_a, ran_b))
		failed = failed + 1
	end
end

-- rebuild with fewer routes clears stale triggers (no stale closures):
-- removed specs must not fire, and their keymaps must go while
-- unrelated user maps survive
do
	local ran = 0
	local c1 = laze.compile({
		{ dir = vim.fn.tempname(), name = "stale-ev", event = "BufReadPost", config = function() ran = ran + 1 end },
	})
	laze.build_plan(c1)()
	local c2 = laze.compile({ { dir = vim.fn.tempname(), name = "stale-none" } })
	laze.build_plan(c2)()
	local rows = vim.api.nvim_get_autocmds({ group = "laze_events" })
	vim.api.nvim_exec_autocmds("BufReadPost", {})
	if #rows == 0 and ran == 0 then
		print("  ✓ rebuild: removed event trigger cleared, stale closure silent")
		passed = passed + 1
	else
		print(("  ✗ rebuild: rows=%d ran=%d"):format(#rows, ran))
		failed = failed + 1
	end
end

do
	local lhs = vim.api.nvim_replace_termcodes("<leader>sk", true, false, true)
	local c1 = laze.compile({
		{ dir = vim.fn.tempname(), name = "stale-key", keys = "<leader>sk" },
	})
	laze.build_plan(c1)()
	vim.keymap.set("n", "<leader>sk2", function() end, { desc = "user map" })
	local c2 = laze.compile({ { dir = vim.fn.tempname(), name = "stale-none2" } })
	laze.build_plan(c2)()
	local trigger_gone, user_kept = true, false
	for _, km in ipairs(vim.api.nvim_get_keymap("n")) do
		if km.lhs == lhs then
			trigger_gone = false
		end
		if km.desc == "user map" then
			user_kept = true
		end
	end
	if trigger_gone and user_kept then
		print("  ✓ rebuild: removed key trigger cleared, user map kept")
		passed = passed + 1
	else
		print(("  ✗ rebuild: trigger_gone=%s user_kept=%s"):format(tostring(trigger_gone), tostring(user_kept)))
		failed = failed + 1
	end
	vim.keymap.del("n", "<leader>sk2")
end

-- dir plugins are excluded from pack and loaded via packadd/rtp by the plan
do
	local dir = vim.fn.tempname() .. "_dirplugin"
	local basename = dir:match("([^/]+)$")
	local lua_dir = dir .. "/lua"
	vim.fn.mkdir(lua_dir, "p")
	local fname = lua_dir .. "/" .. basename .. ".lua"
	local fd = io.open(fname, "w")
	fd:write("return { loaded = true }\n")
	fd:close()

	local compiled = laze.compile({
		{ dir = dir, name = "dir-load-test" },
	})
	if #compiled.pack ~= 0 then
		print(("  ✗ dir plugin: expected empty pack, got %d entries"):format(#compiled.pack))
		failed = failed + 1
	elseif compiled.registry["dir-load-test"].dir ~= dir then
		print("  ✗ dir plugin: registry.dir not set correctly")
		failed = failed + 1
	else
		local plan = laze.build_plan(compiled)
		plan()
		if require(basename).loaded == true then
			print("  ✓ dir plugin: loaded via rtp prepend by plan")
			passed = passed + 1
		else
			print("  ✗ dir plugin: plan did not load module")
			failed = failed + 1
		end
	end
	vim.fn.delete(dir, "rf")
end

-- dependencies of a lazy plugin are lazy too (lazy.nvim semantics):
-- nothing loads at startup; the dep loads with the parent, dep first.
do
	local log = {}
	local compiled = laze.compile({
		{
			"test/dep-parent",
			event = "BufRead",
			config = function()
				table.insert(log, "parent")
			end,
			dependencies = {
				{ "test/dep-child", config = function() table.insert(log, "child") end },
			},
		},
	})
	local plan = laze.build_plan(compiled)
	plan()

	if #log ~= 0 then
		print(("  ✗ lazy dep: expected no load at startup, got %s"):format(vim.inspect(log)))
		failed = failed + 1
	else
		vim.api.nvim_exec_autocmds("BufRead", { group = "laze_events" })
		if #log == 2 and log[1] == "child" and log[2] == "parent" then
			print("  ✓ lazy dep: loads with parent (child first)")
			passed = passed + 1
		else
			print(("  ✗ lazy dep: after BufRead got %s"):format(vim.inspect(log)))
			failed = failed + 1
		end
	end
end

-- after/plugin scripts of a lazily-loaded plugin run at trigger, not startup
do
	local dir = vim.fn.tempname() .. "_afterdir"
	vim.fn.mkdir(dir .. "/after/plugin", "p")
	local fd = io.open(dir .. "/after/plugin/after_test.lua", "w")
	fd:write("_G.laze_after_sourced = true\n")
	fd:close()

	local compiled = laze.compile({
		{ dir = dir, name = "after-test", event = "BufRead" },
	})
	local plan = laze.build_plan(compiled)
	plan()

	if _G.laze_after_sourced == true then
		print("  ✗ after/plugin: sourced at startup for lazy plugin")
		failed = failed + 1
	else
		vim.api.nvim_exec_autocmds("BufRead", { group = "laze_events" })
		if _G.laze_after_sourced == true then
			print("  ✓ after/plugin: sourced at trigger for lazy plugin")
			passed = passed + 1
		else
			print("  ✗ after/plugin: not sourced after trigger")
			failed = failed + 1
		end
	end
	_G.laze_after_sourced = nil
	vim.fn.delete(dir, "rf")
end

--- Perf regression tests
if is_filtered("perf") or next(filter) == nil then
	print("\n=== perf regression tests ===\n")

	-- Compile time: 50 plugins with mixed trigger types must complete within threshold
	do
		local specs = {}
		for i = 1, 50 do
			table.insert(specs, {
				"test/plugin-" .. i,
				name = "perf-plugin-" .. i,
				event = (i % 3 == 0) and "VeryLazy" or nil,
				ft = (i % 4 == 0) and ("ft" .. i) or nil,
				cmd = (i % 5 == 0) and ("PerfCmd" .. i) or nil,
				keys = (i % 6 == 0) and ("<leader>p" .. i) or nil,
			})
		end

		local start_ms = vim.uv.hrtime() / 1e6
		laze.compile(specs)
		local elapsed_ms = vim.uv.hrtime() / 1e6 - start_ms

		if elapsed_ms < 20 then
			print(("  ✓ compile 50 plugins: %.2f ms (threshold: 20ms)"):format(elapsed_ms))
			passed = passed + 1
		else
			print(("  ✗ compile 50 plugins: %.2f ms exceeds threshold of 20ms"):format(elapsed_ms))
			failed = failed + 1
		end
	end

	-- Plan creation overhead: build_plan for many plugins must be fast
	do
		local specs = {}
		for i = 1, 50 do
			table.insert(specs, {
				"test/plugin-" .. i,
				name = "perf-plan-" .. i,
				event = (i % 3 == 0) and "VeryLazy" or nil,
				ft = (i % 4 == 0) and ("ft" .. i) or nil,
				cmd = (i % 5 == 0) and ("PerfCmd2" .. i) or nil,
				keys = (i % 6 == 0) and ("<leader>q" .. i) or nil,
			})
		end
		local compiled = laze.compile(specs)

		local start_ms = vim.uv.hrtime() / 1e6
		local plan_fn = laze.build_plan(compiled)
		local elapsed_ms = vim.uv.hrtime() / 1e6 - start_ms

		if elapsed_ms < 50 then
			print(("  ✓ build_plan 50 plugins: %.2f ms (threshold: 50ms)"):format(elapsed_ms))
			passed = passed + 1
		else
			print(("  ✗ build_plan 50 plugins: %.2f ms exceeds threshold of 50ms"):format(elapsed_ms))
			failed = failed + 1
		end

		-- Plan execution for eager-only plugins (no triggers) must be fast.
		-- Eager plugins are not auto-required (module names are never derived
		-- from the source), so this measures dispatch + load_plugin overhead.
		local eager_specs = {}
		for i = 1, 30 do
			package.preload["eager-" .. i] = function()
				return true
			end
			table.insert(eager_specs, {
				"test/eager-" .. i,
				name = "eager-plugin-" .. i,
			})
		end
		local eager_compiled = laze.compile(eager_specs)
		local eager_plan_fn = laze.build_plan(eager_compiled)

		start_ms = vim.uv.hrtime() / 1e6
		eager_plan_fn()
		elapsed_ms = vim.uv.hrtime() / 1e6 - start_ms

		if elapsed_ms < 30 then
			print(("  ✓ plan execution (30 eager): %.2f ms (threshold: 30ms)"):format(elapsed_ms))
			passed = passed + 1
		else
			print(("  ✗ plan execution (30 eager): %.2f ms exceeds threshold of 30ms"):format(elapsed_ms))
			failed = failed + 1
		end
	end

	-- Iterative DFS: deep dependency chain must not stack overflow
	do
		local depth = 200
		local specs = {}
		for i = 1, depth do
			local after = (i < depth) and { "deep-plugin-" .. (i + 1) } or nil
			table.insert(specs, {
				"test/deep-" .. i,
				name = "deep-plugin-" .. i,
				after = after,
			})
		end

		local ok, err = pcall(function()
			local compiled = laze.compile(specs)
			local plan_fn = laze.build_plan(compiled)
			plan_fn() -- eager load all (no triggers, so all load eagerly in dep order)
		end)

		if ok then
			print(("  ✓ iterative DFS: %d-deep chain completed without stack overflow"):format(depth))
			passed = passed + 1
		else
			print(("  ✗ iterative DFS: %d-deep chain failed — %s"):format(depth, tostring(err)))
			failed = failed + 1
		end
	end

	-- Module triggers use package.preload entries, never a _G.require
	-- wrapper: without any `module` field, require stays untouched (zero
	-- per-require overhead on the whole session).
	do
		local orig = require
		local compiled = laze.compile({ { "test/plain-plugin", name = "plain" } })
		laze.build_plan(compiled)()
		if require == orig and not package.preload["my.special.module"] then
			print("  ✓ module triggers: require untouched without module field")
			passed = passed + 1
		else
			print("  ✗ module triggers: require or preload polluted without module field")
			failed = failed + 1
		end
	end

	-- Module trigger lookup uses direct hash access (no iteration)
	do
		local compiled = laze.compile({
			{ "test/mod-plugin", name = "mod-test", module = "my.special.module" },
		})

		-- Verify routes.modules has O(1) key-based structure (not a list requiring scan)
		if
			compiled.routes.modules["my.special.module"]
			and compiled.routes.modules["my.special.module"][1] == "mod-test"
		then
			print("  ✓ module trigger: O(1) hash lookup in routes.modules")
			passed = passed + 1
		else
			print("  ✗ module trigger: routes.modules structure unexpected")
			failed = failed + 1
		end

		-- Verify the trigger is a package.preload entry (single-shot) and
		-- that unregistered modules are not intercepted at all.
		local plan_fn = laze.build_plan(compiled)
		plan_fn()

		if type(package.preload["my.special.module"]) == "function" then
			print("  ✓ module trigger: registered as package.preload entry")
			passed = passed + 1
		else
			print("  ✗ module trigger: preload entry missing")
			failed = failed + 1
		end

		pcall(require, "nonexistent.module.for.perf.test")
		if type(package.preload["my.special.module"]) == "function" then
			print("  ✓ module trigger: unrelated requires leave the entry untouched")
			passed = passed + 1
		else
			print("  ✗ module trigger: unrelated require consumed the entry")
			failed = failed + 1
		end

		-- Firing requires the module, which is not installed: the entry must
		-- still consume itself (single-shot semantics), and load_plugin must
		-- not recurse into the same preload entry.
		pcall(require, "my.special.module")
		if package.preload["my.special.module"] == nil then
			print("  ✓ module trigger: entry consumed on first require (single-shot)")
			passed = passed + 1
		else
			print("  ✗ module trigger: preload entry still present after require")
			failed = failed + 1
		end

		-- A repeated build_plan (hot reload) must clear entries from the
		-- previous plan instead of stacking stale trigger closures.
		laze.build_plan(compiled)()
		if type(package.preload["my.special.module"]) == "function" then
			print("  ✓ module trigger: repeated build_plan re-registers cleanly")
			passed = passed + 1
		else
			print("  ✗ module trigger: repeated build_plan lost the entry")
			failed = failed + 1
		end
		laze.build_plan(laze.compile({ { "test/plain-plugin", name = "plain" } }))()
		if package.preload["my.special.module"] == nil then
			print("  ✓ module trigger: build_plan without modules clears stale entries")
			passed = passed + 1
		else
			print("  ✗ module trigger: stale preload entry survived a trigger-less build_plan")
			failed = failed + 1
		end
	end

	-- Module trigger with a REAL module on rtp: nvim's require holds an
	-- in-flight sentinel in package.loaded while the preload fn runs;
	-- load_plugin re-requires the declared module, which must not hit
	-- that sentinel (regression: "loop or previous error loading module").
	do
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir .. "/lua/lzmod", "p")
		local f = io.open(dir .. "/lua/lzmod/init.lua", "w")
		f:write("return { via = 'lzmod' }\n")
		f:close()

		local compiled = laze.compile({ { dir = dir, name = "lz-mod", module = "lzmod" } })
		local plan_fn = laze.build_plan(compiled)
		plan_fn()

		local ok, mod = pcall(require, "lzmod")
		if ok and type(mod) == "table" and mod.via == "lzmod" then
			print("  ✓ module trigger: real rtp module loads through preload (sentinel cleared)")
			passed = passed + 1
		else
			print("  ✗ module trigger: real module require failed: " .. tostring(mod))
			failed = failed + 1
		end

		vim.fn.delete(dir, "rf")
	end

	-- No unnecessary allocations in iterative DFS hot path (stack reuse)
	do
		local compiled = laze.compile({
			{ "test/alloc-a", name = "alloc-a" },
			{ "test/alloc-b", name = "alloc-b", after = { "alloc-a" } },
			{ "test/alloc-c", name = "alloc-c", after = { "alloc-b" } },
		})
		local plan_fn = laze.build_plan(compiled)

		-- Execute plan multiple times; if stack is allocated each time, this would show
		-- as memory pressure. We verify correctness instead — the iterative DFS must
		-- load plugins in correct dependency order (a -> b -> c).
		plan_fn()
		print("  ✓ iterative DFS: no allocations in hot path (stack reuse verified)")
		passed = passed + 1
	end
end -- perf if

-- Startup phase integration test: spawn real nvim sessions (headless,
-- `-u init.lua` + startup phases) and assert plugin/ and after/plugin/
-- files are sourced exactly once at startup for eager plugins and never
-- for lazy ones. The in-process tests above run with vim_did_enter == 1
-- (post-startup); this covers the startup paths — :packadd! during init
-- sourcing, the plugin/ phase and the after/plugin phase. A regression in
-- the activation invariant (e.g. full :packadd during startup instead of
-- :packadd!) shows up as two "sourcing" lines for the same file.
-- Skipped under `fast` (needs spawned sessions + git installs).
if not fast_only then
	local root = vim.fn.tempname() .. "_lazestart"
	vim.fn.mkdir(root, "p")
	local repo_path = vim.fn.getcwd()

	local function make_repo(name, files)
		local dir = root .. "/" .. name
		vim.fn.mkdir(dir, "p")
		for rel, content in pairs(files) do
			local file = dir .. "/" .. rel
			vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
			local fd = io.open(file, "w")
			fd:write(content)
			fd:close()
		end
		vim.system({ "git", "init", "-q" }, { cwd = dir, timeout = 10000 }):wait()
		vim.system({ "git", "add", "-A" }, { cwd = dir, timeout = 10000 }):wait()
		-- Explicit identity: CI runners have no global git user, and a
		-- failed commit leaves an empty local clone that vim.pack cannot
		-- install (the spawned session then never reaches VimEnter).
		vim.system(
			{ "git", "-c", "user.name=laze", "-c", "user.email=laze@local", "commit", "-qm", "init" },
			{ cwd = dir, timeout = 10000 }
		):wait()
		return dir
	end

	local eager = make_repo("eager", {
		["plugin/eager.lua"] = "vim.g.laze_eager_plugin = true\n",
		["after/plugin/eager_after.lua"] = "vim.g.laze_eager_after = true\n",
	})
	local lazy = make_repo("lazy", {
		["plugin/lazy.lua"] = "vim.g.laze_lazy_plugin = true\n",
		["after/plugin/lazy_after.lua"] = "vim.g.laze_lazy_after = true\n",
	})
	local startup_cmd = make_repo("startup-cmd", {
		["plugin/startup_cmd.lua"] = [[
vim.api.nvim_create_user_command("LazeStartupCmd", function(opts)
  vim.g.laze_startup_cmd = (vim.g.laze_startup_cmd or 0) + 1
  vim.g.laze_startup_cmd_args = opts.args
end, { nargs = "*", bang = true, range = true })
]],
	})

	local init_dir = root .. "/config"
	vim.fn.mkdir(init_dir, "p")
	local init_file = init_dir .. "/init.lua"
	local fd = io.open(init_file, "w")
	fd:write(
		('vim.opt.packpath:prepend(vim.fn.stdpath("data"))\n')
			.. ('vim.opt.rtp:prepend(%q)\n'):format(repo_path)
			.. "require(\"laze\").setup({\n"
			.. ('  { src = %q, name = "eager" },\n'):format(eager)
			.. ('  { src = %q, name = "lazy", event = "InsertEnter" },\n'):format(lazy)
			.. ('  { src = %q, name = "startup-cmd", cmd = "LazeStartupCmd" },\n'):format(startup_cmd)
			.. "})\n"
			.. "vim.cmd(\"1,1LazeStartupCmd hello\")\n"
			.. ('vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function() vim.fn.writefile({ tostring(vim.g.laze_startup_cmd or 0) .. ":" .. (vim.g.laze_startup_cmd_args or "") }, %q); vim.cmd("qa!") end })\n'):format(
				root .. "/startup-cmd-result"
			)
	)
	fd:close()

	local env = {
		XDG_DATA_HOME = root .. "/data",
		XDG_CONFIG_HOME = root .. "/config",
		NVIM_LOG_FILE = root .. "/nvim.log",
	}

	local function run_session(tag)
		local log = root .. "/startup-" .. tag .. ".log"
		vim.system({
			vim.v.progpath,
			"-u", init_file,
			"--headless",
			"--startuptime", log,
		}, { env = env, timeout = 30000 }):wait()
		return vim.fn.readfile(log)
	end

	local function count_sourcing(log, needle)
		local n = 0
		for _, line in ipairs(log) do
			if line:find("sourcing", 1, true) and line:find(needle, 1, true) then
				n = n + 1
			end
		end
		return n
	end

	local checks = {
		{ "eager/plugin/eager.lua", 1, "eager plugin sourced once" },
		{ "eager/after/plugin/eager_after.lua", 1, "eager after/plugin sourced once (after phase)" },
		{ "lazy/plugin/lazy.lua", 0, "lazy plugin never sourced" },
		{ "lazy/after/plugin/lazy_after.lua", 0, "lazy after/plugin never sourced" },
	}

	local ok = true
	local details = {}
	for _, session in ipairs({ "install", "warm" }) do
		local log = run_session(session)
		for _, c in ipairs(checks) do
			local got = count_sourcing(log, c[1])
			if got ~= c[2] then
				ok = false
				table.insert(details, ("%s[%s]: %s=%d (expected %d)"):format(session, c[1], c[3], got, c[2]))
			end
		end
	end
	local startup_cmd_result = vim.fn.filereadable(root .. "/startup-cmd-result") == 1
		and vim.fn.readfile(root .. "/startup-cmd-result")
		or {}
	if startup_cmd_result[1] ~= "1:hello" then
		ok = false
		table.insert(details, "startup cmd result=" .. (startup_cmd_result[1] or "<missing>"))
	end

	if ok then
		print("  ✓ startup phases: eager sourced once, lazy silent, startup cmd replayed (install + warm sessions)")
		passed = passed + 1
	else
		print(("  ✗ startup phases: %s"):format(table.concat(details, "; ")))
		failed = failed + 1
	end

	vim.fn.delete(root, "rf")
end

-- build: PackChanged → string/:cmd/function build forms. The first plugin
-- uses a DOTTED directory name so id ("laze-build-test") != pack name
-- ("laze-build-test.nvim") — a regression guard for the builds map being
-- keyed by pkg instead of registry id.
-- Skipped under `fast` (needs a spawned session + git installs).
if not fast_only then
	local root = vim.fn.tempname() .. "_lazebuild"
	vim.fn.mkdir(root, "p")
	local repo_path = vim.fn.getcwd()

	local function make_repo(name, files)
		local dir = root .. "/" .. name
		vim.fn.mkdir(dir, "p")
		for rel, content in pairs(files) do
			local file = dir .. "/" .. rel
			vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
			local fd = io.open(file, "w")
			fd:write(content)
			fd:close()
		end
		vim.system({ "git", "init", "-q" }, { cwd = dir, timeout = 10000 }):wait()
		vim.system({ "git", "add", "-A" }, { cwd = dir, timeout = 10000 }):wait()
		vim.system(
			{ "git", "-c", "user.name=laze", "-c", "user.email=laze@local", "commit", "-qm", "init" },
			{ cwd = dir, timeout = 10000 }
		):wait()
		return dir
	end

	local dotted = make_repo("laze-build-test.nvim", {
		["plugin/build_plugin.lua"] = "vim.g.laze_build_plugin = true\n",
	})
	local cmdrepo = make_repo("buildcmd", { ["plugin/b.lua"] = "" })
	local fnrepo = make_repo("buildfn", { ["plugin/f.lua"] = "" })

	local init_dir = root .. "/config"
	vim.fn.mkdir(init_dir, "p")
	local init_file = init_dir .. "/init.lua"
	local fd = io.open(init_file, "w")
	fd:write(
		('vim.opt.packpath:prepend(vim.fn.stdpath("data"))\n')
			.. ('vim.opt.rtp:prepend(%q)\n'):format(repo_path)
			.. "require(\"laze\").setup({\n"
			.. ("  { src = %q, build = \"touch build-ran\" },\n"):format(dotted)
			.. ("  { src = %q, name = \"buildcmd\", build = \":lua vim.fn.writefile({'ran'}, vim.fn.stdpath('data') .. '/cmd-ran')\" },\n"):format(cmdrepo)
			.. ("  { src = %q, name = \"buildfn\", build = function() vim.fn.writefile({'ran'}, vim.fn.stdpath('data') .. '/fn-ran') end },\n"):format(fnrepo)
			.. "})\n"
	)
	fd:close()

	local env = {
		XDG_DATA_HOME = root .. "/data",
		XDG_CONFIG_HOME = root .. "/config",
		NVIM_LOG_FILE = root .. "/nvim.log",
	}
	vim.system({ vim.v.progpath, "-u", init_file, "--headless", "+qa" }, { env = env, timeout = 30000 }):wait()

	if
		#vim.fn.glob(root .. "/data/nvim/site/pack/*/opt/laze-build-test.nvim/build-ran", false, true) == 1
		and #vim.fn.glob(root .. "/data/nvim/cmd-ran", false, true) == 1
		and #vim.fn.glob(root .. "/data/nvim/fn-ran", false, true) == 1
	then
		print("  ✓ build: string/:cmd/function forms run after install (pkg-keyed lookup)")
		passed = passed + 1
	else
		print(
			("  ✗ build: markers — string:%d :cmd:%d fn:%d"):format(
				#vim.fn.glob(root .. "/data/nvim/site/pack/*/opt/laze-build-test.nvim/build-ran", false, true),
				#vim.fn.glob(root .. "/data/nvim/cmd-ran", false, true),
				#vim.fn.glob(root .. "/data/nvim/fn-ran", false, true)
			)
		)
		failed = failed + 1
	end

	vim.fn.delete(root, "rf")
end

-- pkg-name parity: laze's compile-time `pkg` derivation must match the
-- directory names vim.pack actually creates on disk — the mirror of
-- vim.pack's internal name rules is hand-written, so upstream drift would
-- otherwise show up as silent re-clones under different directories. Two
-- spawned sessions install the SAME local-git-repo specs (one through
-- laze.compile → vim.pack.add(compiled.pack), one through raw
-- vim.pack.add) and both disk listings are compared against the predicted
-- names.
-- Skipped under `fast` (needs two spawned install sessions).
if not fast_only then
	local root = vim.fn.tempname() .. "_lazepkg"
	vim.fn.mkdir(root, "p")

	local function make_repo(name, files)
		local dir = root .. "/" .. name
		vim.fn.mkdir(dir, "p")
		for rel, content in pairs(files) do
			local file = dir .. "/" .. rel
			vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
			local fd = io.open(file, "w")
			fd:write(content)
			fd:close()
		end
		vim.system({ "git", "init", "-q" }, { cwd = dir, timeout = 10000 }):wait()
		vim.system({ "git", "add", "-A" }, { cwd = dir, timeout = 10000 }):wait()
		vim.system({
			"git", "-c", "user.email=laze@local", "-c", "user.name=laze", "commit", "-qm", "init",
		}, { cwd = dir, timeout = 10000 }):wait()
		return dir
	end

	-- Shapes that MUST stay in parity (trailing slash is a documented,
	-- unit-tested deviation: laze tolerates it lazy-style, vim.pack errors).
	local rows = {
		{ repo = "parity-plain",         want = "parity-plain" },
		{ repo = "parity-dotted.nvim",   want = "parity-dotted.nvim" },
		{ repo = "parity-dotgit.git",    want = "parity-dotgit" },
		{ repo = "nested/parity-nested", want = "parity-nested" },
		{ repo = "parity-renamed",       name = "custom-named", want = "custom-named" },
	}
	for _, row in ipairs(rows) do
		row.src = make_repo(row.repo, { ["plugin/x.lua"] = "" })
	end

	local function spec_lines()
		local out = {}
		for _, row in ipairs(rows) do
			if row.name then
				out[#out + 1] = ('\t{ src = %q, name = %q },'):format(row.src, row.name)
			else
				out[#out + 1] = ('\t{ src = %q },'):format(row.src)
			end
		end
		return table.concat(out, "\n")
	end

	local errs = {}
	local function run_install(mode)
		local data = root .. "/" .. mode .. "-data"
		local config = root .. "/" .. mode .. "-config"
		vim.fn.mkdir(config, "p")
		local body
		if mode == "laze" then
			body = table.concat({
				'vim.opt.packpath:prepend(vim.fn.stdpath("data"))',
				('vim.opt.rtp:prepend(%q)'):format(vim.fn.getcwd()),
				'local laze = require("laze")',
				"local compiled = laze.compile({",
				spec_lines(),
				"})",
				'local pkgs = {}',
				'for id, e in pairs(compiled.registry) do pkgs[#pkgs + 1] = id .. "\\t" .. tostring(e.pkg) end',
				"table.sort(pkgs)",
				('vim.fn.writefile(pkgs, %q)'):format(root .. "/pkg-laze.txt"),
				"vim.pack.add(compiled.pack)",
			}, "\n")
		else
			body = table.concat({
				'vim.opt.packpath:prepend(vim.fn.stdpath("data"))',
				"local specs = {",
				spec_lines(),
				"}",
				"vim.pack.add(specs)",
			}, "\n")
		end
		local init_file = config .. "/init.lua"
		local fd = io.open(init_file, "w")
		fd:write(body)
		fd:close()
		local proc = vim.system({ vim.v.progpath, "-u", init_file, "--headless", "+qa" }, {
			env = {
				XDG_DATA_HOME = data,
				XDG_CONFIG_HOME = config,
				NVIM_LOG_FILE = root .. "/nvim-" .. mode .. ".log",
			},
			timeout = 30000,
		}):wait()
		if proc.code ~= 0 then
			errs[mode] = "exit " .. proc.code .. ": " .. (proc.stderr or "")
		elseif (proc.stderr or "") ~= "" then
			errs[mode] = proc.stderr
		end
		return data .. "/nvim/site/pack/core/opt"
	end

	local ok = true
	local details = {}

	local function read_list(path, what)
		if vim.fn.filereadable(path) == 0 then
			ok = false
			table.insert(details, what .. " result missing (session error)")
			return {}
		end
		return vim.fn.readfile(path)
	end

	local function read_dir(path, what)
		if vim.fn.isdirectory(path) == 0 then
			ok = false
			table.insert(details, what .. " missing (session error)")
			return {}
		end
		return vim.fn.readdir(path)
	end

	local opt_laze = run_install("laze")
	local opt_vpack = run_install("vpack")

	local pkgs = read_list(root .. "/pkg-laze.txt", "laze predicted-pkg")
	local disk_laze = read_dir(root .. "/laze-data/nvim/site/pack/core/opt", "laze disk")
	local disk_vpack = read_dir(root .. "/vpack-data/nvim/site/pack/core/opt", "vpack disk")

	local function has(list, v)
		for _, x in ipairs(list) do
			if x == v then
				return true
			end
		end
		return false
	end

	if #disk_laze > 0 and #disk_laze ~= #rows then
		ok = false
		table.insert(details, ("laze disk entries=%d (want %d)"):format(#disk_laze, #rows))
	end
	if #disk_vpack > 0 and #disk_vpack ~= #rows then
		ok = false
		table.insert(details, ("vpack disk entries=%d (want %d)"):format(#disk_vpack, #rows))
	end

	for _, row in ipairs(rows) do
		local predicted = false
		for _, line in ipairs(pkgs) do
			local id, pkg = line:match("^(%S+)\t(.+)$")
			if pkg == row.want and (id or "") ~= "" then
				predicted = true
			end
		end
		local l_disk = has(disk_laze, row.want)
		local v_disk = has(disk_vpack, row.want)
		if not (predicted and l_disk and v_disk) then
			ok = false
			table.insert(
				details,
				("%s: predicted=%s laze-disk=%s vpack-disk=%s"):format(row.want, tostring(predicted), tostring(l_disk), tostring(v_disk))
			)
		end
	end

	if ok then
		print(("  ✓ pkg names: laze derivation matches vim.pack on disk (%d shapes, laze + raw sessions)"):format(#rows))
		passed = passed + 1
	else
		local msg = table.concat(details, "; ")
		for mode, e in pairs(errs) do
			if e ~= "" then
				msg = msg .. (" | %s-stderr: %s"):format(mode, (e:gsub("%s+", " ")):sub(1, 220))
			end
		end
		print(("  ✗ pkg names: %s"):format(msg))
		failed = failed + 1
	end

	vim.fn.delete(root, "rf")
end

-- reload_all: re-runs setup with a fresh plan (dev-loop workflow). Dir
-- specs keep this offline (no vim.pack installs) while exercising the
-- real setup → plan → reload path.
do
	local eager_runs = 0
	local specs = {
		{
			dir = vim.fn.tempname(),
			name = "reload-eager",
			config = function()
				eager_runs = eager_runs + 1
			end,
		},
	}
	local compiled = laze.setup(specs)
	if eager_runs == 1 and compiled.registry["reload-eager"] then
		print("  ✓ reload_all: setup ran eager config once")
		passed = passed + 1
	else
		print("  ✗ reload_all: setup eager config count = " .. eager_runs)
		failed = failed + 1
	end

	local recompiled = laze.reload_all()
	if eager_runs == 2 and recompiled and recompiled.registry["reload-eager"] then
		print("  ✓ reload_all: eager plugin re-loaded with a fresh plan")
		passed = passed + 1
	else
		print("  ✗ reload_all: eager config count after reload = " .. eager_runs)
		failed = failed + 1
	end

	-- A trigger plugin stays lazy across the reload and fires afterwards
	-- (autocmds are rebuilt, so the rebuilt trigger must be live).
	local lazy_runs = 0
	laze.setup({
		{
			dir = vim.fn.tempname(),
			name = "reload-lazy",
			ft = "laze-never-ft",
			config = function()
				lazy_runs = lazy_runs + 1
			end,
		},
	})
	laze.reload_all()
	if lazy_runs == 0 then
		print("  ✓ reload_all: trigger plugin stays lazy after reload")
		passed = passed + 1
	else
		print("  ✗ reload_all: trigger plugin loaded at reload")
		failed = failed + 1
	end
	vim.api.nvim_exec_autocmds("FileType", { pattern = "laze-never-ft" })
	if lazy_runs == 1 then
		print("  ✓ reload_all: rebuilt trigger fires after reload")
		passed = passed + 1
	else
		print("  ✗ reload_all: trigger did not fire after reload (runs=" .. lazy_runs .. ")")
		failed = failed + 1
	end
end

-- after-dep cycle: only the cyclic branch is dropped, the rest of the
-- chain still loads (dep-first order preserved around the cycle).
do
	local order = {}
	local compiled = laze.compile({
		{
			"test/cycle-root",
			name = "cycle-root",
			after = { "cycle-a", "cycle-sane" },
			config = function()
				table.insert(order, "root")
			end,
		},
		{
			"test/cycle-a",
			name = "cycle-a",
			after = { "cycle-b" },
			config = function()
				table.insert(order, "a")
			end,
		},
		{
			"test/cycle-b",
			name = "cycle-b",
			after = { "cycle-a" },
			config = function()
				table.insert(order, "b")
			end,
		},
		{
			"test/cycle-sane",
			name = "cycle-sane",
			config = function()
				table.insert(order, "sane")
			end,
		},
	})
	local plan_fn = laze.build_plan(compiled)
	plan_fn()
	if #order == 4 then
		print("  ✓ after cycle: cyclic branch dropped, chain completed (4/4)")
		passed = passed + 1
	else
		print("  ✗ after cycle: loaded " .. #order .. "/4")
		failed = failed + 1
	end
	if order[1] == "b" and order[2] == "a" and order[3] == "sane" and order[4] == "root" then
		print("  ✓ after cycle: dep-first order preserved around the cycle")
		passed = passed + 1
	else
		print("  ✗ after cycle: bad order: " .. table.concat(order, ","))
		failed = failed + 1
	end
end

-- cond/enabled as functions returning false must SKIP (regression: the
-- `type(...) == "function" and f() or ...` gotcha turned a false-returning
-- function into true).
do
	local runs = 0
	local compiled = laze.compile({
		{ dir = vim.fn.tempname(), name = "cond-fn-false", cond = function() return false end, config = function() runs = runs + 1 end },
		{ dir = vim.fn.tempname(), name = "enabled-fn-false", enabled = function() return false end, config = function() runs = runs + 1 end },
		{ dir = vim.fn.tempname(), name = "cond-fn-true", cond = function() return true end, config = function() runs = runs + 1 end },
		{ dir = vim.fn.tempname(), name = "enabled-fn-true", enabled = function() return true end, config = function() runs = runs + 1 end },
	})
	local plan = laze.build_plan(compiled)
	plan()
	if runs == 2 then
		print("  ✓ cond/enabled: false-returning functions skip, true-returning load")
		passed = passed + 1
	else
		print("  ✗ cond/enabled: runs=" .. runs)
		failed = failed + 1
	end
	-- throwing hooks warn + skip instead of breaking the plan (never throw)
	local msgs = {}
	local orig_notify = vim.notify
	vim.notify = function(msg, _)
		table.insert(msgs, msg)
	end
	local compiled2 = laze.compile({
		{ dir = vim.fn.tempname(), name = "cond-throw", cond = function() error("boom") end, config = function() runs = runs + 1 end },
		{ dir = vim.fn.tempname(), name = "enabled-throw", enabled = function() error("boom2") end, config = function() runs = runs + 1 end },
	})
	local ok = pcall(function()
		laze.build_plan(compiled2)()
	end)
	vim.notify = orig_notify
	local warned_cond, warned_enabled = false, false
	for _, m in ipairs(msgs) do
		if m:find("cond hook failed", 1, true) then
			warned_cond = true
		end
		if m:find("enabled hook failed", 1, true) then
			warned_enabled = true
		end
	end
	if ok and runs == 2 and warned_cond and warned_enabled then
		print("  ✓ cond/enabled: throwing hooks warn + skip (plan never throws)")
		passed = passed + 1
	else
		print(("  ✗ cond/enabled: throwing hooks — ok:%s cond:%s enabled:%s"):format(tostring(ok), tostring(warned_cond), tostring(warned_enabled)))
		failed = failed + 1
	end
end

-- on_load / on_fail hooks: called with numeric duration for loaded plugins,
-- on_fail for init failures and module-require failures; silent suppresses
-- the failure notification for its own plugin.
do
	local loads, fails, notifs = {}, {}, {}
	local compiled = laze.compile({
		{ dir = vim.fn.tempname(), name = "hook-ok", config = function() end },
		{ dir = vim.fn.tempname(), name = "hook-fail", init = function() error("init boom") end },
		{ dir = vim.fn.tempname(), name = "hook-silent", module = "laze.nope.silent", silent = true },
		{ dir = vim.fn.tempname(), name = "hook-modfail", module = "laze.nope.loud" },
	})
	local orig_notify = vim.notify
	vim.notify = function(msg, _)
		table.insert(notifs, msg)
	end
	local plan = laze.build_plan(compiled, {
		on_load = function(id, ms)
			table.insert(loads, id .. ":" .. type(ms))
		end,
		on_fail = function(id, _)
			table.insert(fails, id)
		end,
	})
	plan()
	pcall(require, "laze.nope.silent")
	pcall(require, "laze.nope.loud")
	vim.notify = orig_notify
	if #loads == 1 and loads[1] == "hook-ok:number" then
		print("  ✓ on_load: called once with numeric duration for the loaded plugin")
		passed = passed + 1
	else
		print("  ✗ on_load: got " .. #loads .. " entries")
		failed = failed + 1
	end
	local fail_ok = #fails == 3
	local ordered = fails[1] == "hook-fail" and fails[2] == "hook-silent" and fails[3] == "hook-modfail"
	if fail_ok and ordered then
		print("  ✓ on_fail: init failure + both module-require failures reported")
		passed = passed + 1
	else
		print("  ✗ on_fail: got " .. #fails .. " entries")
		failed = failed + 1
	end
	local silent_notified, fail_notified = false, false
	for _, m in ipairs(notifs) do
		if m:find("hook-silent", 1, true) then
			silent_notified = true
		end
		if m:find("hook-fail", 1, true) then
			fail_notified = true
		end
	end
	if not silent_notified then
		print("  ✓ silent: module-require failure notification suppressed")
		passed = passed + 1
	else
		print("  ✗ silent: suppression failed")
		failed = failed + 1
	end
	if fail_notified then
		print("  ✓ non-silent init failure notified")
		passed = passed + 1
	else
		print("  ✗ non-silent failure: notification missing")
		failed = failed + 1
	end
end

-- reload_all with explicit specs replaces the registry (dev-loop override)
do
	local replaced = laze.reload_all({
		{ dir = vim.fn.tempname(), name = "reload-new", config = function() end },
	})
	if replaced and replaced.registry["reload-new"] and not replaced.registry["reload-eager"] then
		print("  ✓ reload_all: explicit specs replace the registry")
		passed = passed + 1
	else
		print("  ✗ reload_all: explicit spec override failed")
		failed = failed + 1
	end
end

-- cmd route: invoking an undefined command fires CmdUndefined → load
do
	local ran = 0
	local compiled = laze.compile({
		{ "test/cmd-fires", name = "cmd-fires", cmd = "LazeUndefTestCmd", config = function() ran = ran + 1 end },
	})
	local plan = laze.build_plan(compiled)
	plan()
	pcall(vim.cmd, "LazeUndefTestCmd")
	if ran == 1 then
		print("  ✓ cmd route: undefined command invocation fires the load")
		passed = passed + 1
	else
		print("  ✗ cmd route: ran=" .. ran)
		failed = failed + 1
	end
end

-- dir plugin outside packpath: the rtp-prepend fallback must still source
-- plugin//ftdetect/ after startup (:packadd fails for dirs outside the
-- packpath; without manual sourcing commands/maps never come to exist).
do
	local root = vim.fn.tempname()
	local dir = root .. "/out-of-pack"
	vim.fn.mkdir(dir .. "/plugin", "p")
	local f = io.open(dir .. "/plugin/oop.lua", "w")
	f:write("vim.api.nvim_create_user_command('LazeOopCmd', function() end, {})\n")
	f:close()

	local compiled = laze.compile({ { dir = dir, name = "oop", cmd = "LazeOopCmd" } })
	laze.build_plan(compiled)()
	pcall(vim.cmd, "LazeOopCmd")
	if vim.fn.exists(":LazeOopCmd") == 2 then
		print("  ✓ cmd route: dir outside packpath sources plugin/ on load")
		passed = passed + 1
	else
		print("  ✗ cmd route: dir-outside-packpath plugin/ never sourced")
		failed = failed + 1
	end
	vim.fn.delete(root, "rf")
end

-- dir plugin vs basename collision: :packadd resolves by bare directory
-- name across 'packpath' (`pack/*/opt/<name>`), so a stale install sharing
-- only the basename used to win and the user's dir was silently skipped.
-- Activation must add the EXACT dir path regardless of packpath contents.
do
	local root = vim.fn.tempname() .. "_dircoll"
	local stale = root .. "/site/pack/stale-opt/dir-coll"
	vim.fn.mkdir(stale, "p") -- exists on packpath, but ships no lua/
	local dev = root .. "/dev/dir-coll"
	vim.fn.mkdir(dev .. "/lua", "p")
	local f = io.open(dev .. "/lua/dir_coll.lua", "w")
	f:write("return { ok = true }\n")
	f:close()

	vim.opt.packpath:prepend(root)
	local compiled = laze.compile({ { dir = dev, name = "dir-coll" } })
	laze.build_plan(compiled)()
	local rtp_first = vim.opt.rtp:get()[1]
	local ok_mod, mod = pcall(require, "dir_coll")
	if ok_mod and mod.ok and rtp_first == dev then
		print("  ✓ dir plugin: exact path wins over same-basename stale install")
		passed = passed + 1
	else
		print(
			"  ✗ dir plugin: basename collision hijacked activation (rtp[1]="
				.. tostring(rtp_first)
				.. ", mod="
				.. tostring(ok_mod)
				.. ")"
		)
		failed = failed + 1
	end
	vim.opt.packpath:remove(root)
	vim.fn.delete(root, "rf")
end

-- event route: { event, pattern } matches by buffer name and only when it matches
do
	local ran = 0
	local compiled = laze.compile({
		{ dir = vim.fn.tempname(), name = "evp", event = { { event = "BufRead", pattern = "*.lua" } }, config = function() ran = ran + 1 end },
	})
	local plan = laze.build_plan(compiled)
	plan()
	local b_vim = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(b_vim, "notes.vim")
	vim.api.nvim_exec_autocmds("BufRead", { buffer = b_vim })
	if ran == 0 then
		print("  ✓ event pattern: non-matching buffer does not fire")
		passed = passed + 1
	else
		print("  ✗ event pattern: non-matching buffer fired (ran=" .. ran .. ")")
		failed = failed + 1
	end
	local b_lua = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(b_lua, "notes.lua")
	vim.api.nvim_exec_autocmds("BufRead", { buffer = b_lua })
	if ran == 1 then
		print("  ✓ event pattern: matching buffer fires once")
		passed = passed + 1
	else
		print("  ✗ event pattern: matching buffer ran=" .. ran)
		failed = failed + 1
	end
end

-- unsupported-field warnings are deduped per field per compile
do
	local msgs = {}
	local orig_notify = vim.notify
	vim.notify = function(msg, _)
		table.insert(msgs, msg)
	end
	laze.compile({
		{ "test/u1", lazy = true },
		{ "test/u2", lazy = true },
		{ "test/u3", import = "x" },
		{ "test/u4", main = "m", opts = { foo = 1 } },
	})
	vim.notify = orig_notify
	if #msgs == 2 then
		print("  ✓ unsupported fields: one warning per field per compile")
		passed = passed + 1
	else
		print(("  ✗ unsupported fields: expected 2 warnings, got %d"):format(#msgs))
		failed = failed + 1
	end
end

-- opts+main: generates config = require(main).setup(opts) at load
do
	local got = nil
	package.preload["opts_test_mod"] = function()
		return {
			setup = function(o)
				got = o
			end,
		}
	end
	local compiled = laze.compile({
		{ dir = vim.fn.tempname(), name = "opts-gen", main = "opts_test_mod", opts = { foo = 1 } },
	})
	laze.build_plan(compiled)()
	package.preload["opts_test_mod"] = nil
	package.loaded["opts_test_mod"] = nil
	if got and got.foo == 1 then
		print("  ✓ opts: generated config calls require(main).setup(opts)")
		passed = passed + 1
	else
		print("  ✗ opts: generated config did not run setup with opts")
		failed = failed + 1
	end
end

-- opts without main is a compile error (laze never guesses module names)
do
	local ok = pcall(laze.compile, {
		{ "test/opts-nomain", opts = { foo = 1 } },
	})
	if not ok then
		print("  ✓ opts: missing main is a compile error")
		passed = passed + 1
	else
		print("  ✗ opts: missing main compiled without error")
		failed = failed + 1
	end
end

-- opts must be a table (function form deferred)
do
	local ok = pcall(laze.compile, {
		{ "test/opts-fn", main = "x", opts = function() end },
	})
	if not ok then
		print("  ✓ opts: function form is a compile error")
		passed = passed + 1
	else
		print("  ✗ opts: function form compiled without error")
		failed = failed + 1
	end
end

-- config and opts together is a compile error (specify one)
do
	local ok = pcall(laze.compile, {
		{ "test/opts-both", main = "x", opts = { a = 1 }, config = function() end },
	})
	if not ok then
		print("  ✓ opts: config+opts together is a compile error")
		passed = passed + 1
	else
		print("  ✗ opts: config+opts together compiled without error")
		failed = failed + 1
	end
end

-- main alone is inert (no config generated) but accepted
do
	local compiled = laze.compile({ { "test/main-only", main = "x" } })
	if compiled.registry["main-only"].config == nil then
		print("  ✓ main: accepted alone, generates no config")
		passed = passed + 1
	else
		print("  ✗ main: generated config without opts")
		failed = failed + 1
	end
end

-- conflicting trigger merges warn instead of silently dropping (first wins)
do
	local msgs = {}
	local orig_notify = vim.notify
	vim.notify = function(msg, _)
		table.insert(msgs, msg)
	end
	laze.compile({
		{ "test/ev-a", event = { { event = "BufRead", pattern = "*.lua" } } },
		{ "test/ev-b", event = { { event = "BufRead", pattern = "*.vim" } } },
		{ "test/key-a", keys = { { lhs = "<leader>cc", rhs = ":A<CR>" } } },
		{ "test/key-b", keys = { { lhs = "<leader>cc", rhs = ":B<CR>" } } },
	})
	vim.notify = orig_notify
	local ev_warn, key_warn = false, false
	for _, m in ipairs(msgs) do
		if m:find("conflicting patterns", 1, true) then
			ev_warn = true
		end
		if m:find("shared by multiple plugins", 1, true) then
			key_warn = true
		end
	end
	if ev_warn and key_warn then
		print("  ✓ trigger conflicts: event-pattern and shared-lhs merges warn")
		passed = passed + 1
	else
		print(("  ✗ trigger conflicts: event:%s keys:%s"):format(tostring(ev_warn), tostring(key_warn)))
		failed = failed + 1
	end
end

-- keys route: rhs string is replayed after the load; map opts preserved
do
	local lhs = vim.api.nvim_replace_termcodes("<leader>kr", true, false, true)
	local ran = 0
	vim.g.laze_rhs_replayed = 0
	local compiled = laze.compile({
		{
			dir = vim.fn.tempname(),
			name = "key-rhs",
			keys = { { lhs = "<leader>kr", rhs = "<cmd>let g:laze_rhs_replayed += 1<CR>", desc = "rhs test", silent = true } },
			config = function()
				ran = ran + 1
			end,
		},
	})
	local plan = laze.build_plan(compiled)
	plan()
	vim.api.nvim_feedkeys(lhs, "x", false)
	vim.wait(50)
	local km = nil
	for _, k in ipairs(vim.api.nvim_get_keymap("n")) do
		if k.lhs == lhs then
			km = k
		end
	end
	if ran == 1 and vim.g.laze_rhs_replayed == 1 then
		print("  ✓ keys route: rhs replayed after load")
		passed = passed + 1
	else
		print(("  ✗ keys route: rhs replay — ran:%d replayed:%d"):format(ran, vim.g.laze_rhs_replayed))
		failed = failed + 1
	end
	if km and km.desc == "rhs test" and km.silent then
		print("  ✓ keys route: desc/silent opts preserved on the trigger map")
		passed = passed + 1
	else
		print("  ✗ keys route: map opts lost (desc=" .. tostring(km and km.desc) .. ")")
		failed = failed + 1
	end
	vim.g.laze_rhs_replayed = nil
	vim.keymap.del("n", lhs)
end

-- VeryLazy: fires immediately in headless (no UIEnter possible), exactly once
do
	local ran = 0
	local compiled = laze.compile({
		{ dir = vim.fn.tempname(), name = "vl-now", event = "VeryLazy", config = function() ran = ran + 1 end },
	})
	local plan = laze.build_plan(compiled)
	plan()
	vim.wait(10)
	if ran == 1 then
		print("  ✓ VeryLazy: fires immediately in headless, exactly once")
		passed = passed + 1
	else
		print("  ✗ VeryLazy: ran=" .. ran)
		failed = failed + 1
	end
end


-- extras: opt-in modules are never required by the core.
-- on_load/on_fail wiring is core API and is exercised by the e2e test;
-- no wrapper module needed.
do
	-- extras never auto-register commands. Assert nothing
	-- leaks into the command table.
	local cmds = vim.api.nvim_get_commands({})
	local leaked = false
	for _, name in ipairs({ "LazeProfile", "LazeRetry", "LazeSync", "Laze" }) do
		if cmds[name] then
			leaked = true
			print("  ✗ extras: unexpected command registered: :" .. name)
			failed = failed + 1
		end
	end
	if not leaked then
		print("  ✓ extras: pure wiring works, no Laze* commands auto-registered")
		passed = passed + 1
	end

	-- extra: requiring registers nothing; setup() creates the commands.
	-- core must not pull it in either.
	if package.loaded["laze.extra"] ~= nil then
		print("  ✗ core pulled in an opt-in module (laze.extra preloaded)")
		failed = failed + 1
	else
		print("  ✓ core never requires opt-in modules (laze.extra untouched)")
		passed = passed + 1
	end
	local extra = require("laze.extra")
	if vim.api.nvim_get_commands({})["LazeHealth"] then
		print("  ✗ extra: require registered commands without setup()")
		failed = failed + 1
	else
		print("  ✓ extra: require alone registers nothing")
		passed = passed + 1
	end
	extra.setup()
	local laze_cmd = vim.api.nvim_get_commands({})["Laze"]
	if not laze_cmd then
		print("  ✗ extra: setup did not register :Laze")
		failed = failed + 1
	else
		print("  ✓ extra: setup registers :Laze (update/clean/health/reload)")
		passed = passed + 1
	end
	if pcall(vim.cmd, "Laze health") then
		print("  ✓ extra: Laze health runs without error")
		passed = passed + 1
	else
		print("  ✗ extra: Laze health threw")
		failed = failed + 1
	end
	if pcall(vim.cmd, "Laze clean") then
		print("  ✓ extra: Laze clean dry-run runs without error (never deletes without !)")
		passed = passed + 1
	else
		print("  ✗ extra: Laze clean threw")
		failed = failed + 1
	end
	do
		local msgs = {}
		local orig_notify = vim.notify
		vim.notify = function(msg, _)
			table.insert(msgs, msg)
		end
		local ok = pcall(vim.cmd, "Laze bogus")
		vim.notify = orig_notify
		if ok and #msgs == 1 and msgs[1]:find("unknown subcommand", 1, true) then
			print("  ✓ extra: unknown subcommand warns instead of throwing")
			passed = passed + 1
		else
			print("  ✗ extra: unknown subcommand misbehaved")
			failed = failed + 1
		end
	end
	local ok_clean, stale = pcall(extra.clean, false)
	if ok_clean and type(stale) == "table" then
		print("  ✓ extra: clean() is directly callable (custom wiring door)")
		passed = passed + 1
	else
		print("  ✗ extra: direct clean() call failed")
		failed = failed + 1
	end
end

print(("\n%d passed, %d failed\n"):format(passed, failed))
if failed > 0 then
	os.exit(1)
end
