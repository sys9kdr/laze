-- Benchmark laze.nvim only
-- Run: nvim --cmd "set rtp+=." --headless -l tests/benchmarks/compile_only.lua

-- Auto-detect the repo root (this script lives in tests/benchmarks/).
local script = debug.getinfo(1, "S").source:sub(2)
local LAZE_DIR = vim.env.LAZE_DIR or vim.fn.fnamemodify(script, ":h:h:h")
local PLUGIN_DIR = vim.env.LAZE_PLUGINS or "/tmp/laze-plugins"

if vim.fn.isdirectory(PLUGIN_DIR) == 0 then
	error("plugin dir not found: " .. PLUGIN_DIR .. "\n  clone real plugins first: ./tests/profile/setup.sh", 0)
end

vim.cmd("set rtp+=" .. LAZE_DIR)

local function time_it(fn)
	local start = vim.uv.hrtime()
	fn()
	return (vim.uv.hrtime() - start) / 1e6
end

local SPEC = {
	{ dir = PLUGIN_DIR .. "/plenary.nvim" },
	{ dir = PLUGIN_DIR .. "/nui.nvim", ft = "markdown" },
	{ dir = PLUGIN_DIR .. "/which-key.nvim", event = "VeryLazy", keys = "<leader>wk" },
	{ dir = PLUGIN_DIR .. "/oil.nvim", cmd = "Oil", keys = { { lhs = "<leader>o", mode = "n" } } },
}

local function run_laze()
	require("laze").setup(SPEC)
end

print("=== laze.nvim Cold Start ===")
local t1 = time_it(run_laze)
print(string.format("Time: %.2f ms", t1))

print("\n=== laze.nvim Warm Start (3 runs) ===")
local times = {}
for _ = 1, 3 do
	package.loaded["laze"] = nil
	table.insert(times, time_it(run_laze))
end
table.sort(times)
print(string.format("Median: %.2f ms", times[2]))

vim.cmd("qa!")
