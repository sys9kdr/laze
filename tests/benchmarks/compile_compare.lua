--- Fair Internal Benchmark: laze.nvim vs lazy.nvim setup (ms)
--- Run: nvim -u NONE --headless -l tests/benchmarks/compile_compare.lua
---
--- Each implementation runs in a fresh Neovim process. The parent discards one
--- warmup run per implementation, then reports the median of RUNS runs. This
--- avoids lazy.nvim's one-setup-per-process limit and keeps the measured
--- region to `require()` + `setup()`; the previous harness called
--- `require("lazy").profile()` inside the timed function, which opened the
--- profile UI and inflated lazy.nvim's number.
---
--- Env: LAZE_DIR, LAZY_DIR, LAZE_PLUGINS, LAZE_BENCH_RUNS (default 5).

local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local LAZE_DIR = vim.env.LAZE_DIR or vim.fn.fnamemodify(script, ":h:h:h")
local LAZY_DIR = vim.env.LAZY_DIR or "/tmp/lazy.nvim"
local PLUGIN_DIR = vim.env.LAZE_PLUGINS or "/tmp/laze-plugins"
local RUNS = tonumber(vim.env.LAZE_BENCH_RUNS or "5")
if not RUNS or RUNS < 1 then
	RUNS = 5
end

local SPEC_LAZE = {
	{ dir = PLUGIN_DIR .. "/plenary.nvim" },
	{ dir = PLUGIN_DIR .. "/nui.nvim", ft = "markdown" },
	{ dir = PLUGIN_DIR .. "/which-key.nvim", cmd = "WhichKey", keys = "<leader>wk" },
	{ dir = PLUGIN_DIR .. "/oil.nvim", cmd = "Oil", keys = { { lhs = "<leader>o", mode = "n" } } },
}

local SPEC_LAZY = {
	{ dir = PLUGIN_DIR .. "/plenary.nvim" },
	{ dir = PLUGIN_DIR .. "/nui.nvim", ft = "markdown" },
	{ dir = PLUGIN_DIR .. "/which-key.nvim", cmd = "WhichKey", keys = "<leader>wk" },
	{ dir = PLUGIN_DIR .. "/oil.nvim", cmd = "Oil", keys = { { "<leader>o", mode = "n" } } },
}

local function check_dirs()
	if vim.fn.isdirectory(PLUGIN_DIR) == 0 then
		error("plugin dir not found: " .. PLUGIN_DIR .. "\n  clone real plugins first: ./tests/profile/setup.sh", 0)
	end
	if vim.fn.isdirectory(LAZY_DIR) == 0 then
		error(
			"lazy.nvim not found at "
				.. LAZY_DIR
				.. "\n  clone it first: git clone --depth 1 https://github.com/folke/lazy.nvim "
				.. LAZY_DIR,
			0
		)
	end
end

local function run_child(impl)
	if impl ~= "laze" and impl ~= "lazy" then
		error("unknown implementation: " .. tostring(impl), 0)
	end
	check_dirs()

	-- nvim -l (script mode) sets loadplugins off; lazy.nvim's setup() returns
	-- early on that and leaves its Config uninitialized. Opt back in so the
	-- lazy.nvim side actually runs.
	vim.go.loadplugins = true

	if impl == "laze" then
		vim.cmd("set rtp+=" .. LAZE_DIR)
	else
		vim.cmd("set rtp+=" .. LAZY_DIR)
	end

	local start = vim.uv.hrtime()
	if impl == "laze" then
		require("laze").setup(SPEC_LAZE)
	else
		require("lazy").setup(SPEC_LAZY, {
			headless = { process = false, log = false, task = false, colors = false },
		})
	end
	local ms = (vim.uv.hrtime() - start) / 1e6
	print(("RESULT %s %.3f"):format(impl, ms))
end

local function run_once(impl)
	local res = vim.system(
		{ vim.v.progpath, "-u", "NONE", "--headless", "-l", script },
		{ env = { LAZE_BENCH_IMPL = impl }, text = true, timeout = 30000 }
	):wait()
	-- `print()` in `nvim -l` script mode goes to stderr, not stdout.
	local output = (res.stdout or "") .. (res.stderr or "")
	if res.code ~= 0 then
		error(("benchmark child failed for %s (code %d)\n%s"):format(impl, res.code, output), 0)
	end
	local ms = tonumber(output:match("RESULT%s+%S+%s+([%d%.]+)"))
	if not ms then
		error(("could not parse benchmark output for %s:\n%s"):format(impl, output), 0)
	end
	return ms
end

local function median(t)
	table.sort(t)
	local n = #t
	if n % 2 == 1 then
		return t[(n + 1) / 2]
	end
	return (t[n / 2] + t[n / 2 + 1]) / 2
end

local function stats(t)
	table.sort(t)
	return median(t), t[1], t[#t]
end

local function main()
	check_dirs()

	local impl = vim.env.LAZE_BENCH_IMPL
	if impl then
		run_child(impl)
		vim.cmd("qa!")
		return
	end

	print("=== Fair Internal Benchmark: laze.nvim vs lazy.nvim ===")
	print("Spec: 4 plugins (2 eager, 2 lazy); fresh process per run")
	print(("Runs: %d (plus one discarded warmup per implementation)"):format(RUNS))
	print()

	-- Warm the OS file cache and report the first-run outliers separately.
	local laze_first = run_once("laze")
	local lazy_first = run_once("lazy")
	print(("First run (discarded): laze %.3f ms, lazy.nvim %.3f ms"):format(laze_first, lazy_first))
	print()

	local laze, lazy = {}, {}
	for i = 1, RUNS do
		-- Alternate the order so a monotonic drift (thermal, cache) does not
		-- systematically favour one implementation.
		if i % 2 == 1 then
			laze[i] = run_once("laze")
			lazy[i] = run_once("lazy")
		else
			lazy[i] = run_once("lazy")
			laze[i] = run_once("laze")
		end
	end

	local laze_med, laze_min, laze_max = stats(laze)
	local lazy_med, lazy_min, lazy_max = stats(lazy)

	print(("laze.nvim: median %.3f ms (min %.3f, max %.3f)"):format(laze_med, laze_min, laze_max))
	print(("lazy.nvim: median %.3f ms (min %.3f, max %.3f)"):format(lazy_med, lazy_min, lazy_max))
	print()
	print(("Delta: %.3f ms (lazy - laze)"):format(lazy_med - laze_med))
	print(("Ratio: %.2fx"):format(lazy_med / laze_med))

	vim.cmd("qa!")
end

main()
