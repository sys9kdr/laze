-- Manual e2e harness: exercises every trigger type against real plugins.
-- Prereq: clone plugins first (tests/profile/setup.sh).
-- Run: nvim --cmd "set rtp+=." -l tests/test_e2e.lua
vim.loader.enable()

local laze = require("laze")
local plugin_dir = "/tmp/laze-plugins"

local specs = {
	-- Start plugin — plenary
	{
		dir = plugin_dir .. "/plenary.nvim",
		config = function()
			print("E2E: plenary loaded")
		end,
	},
	-- Lazy-load on filetype
	{
		dir = plugin_dir .. "/nvim-web-devicons",
		ft = "markdown",
		config = function()
			print("E2E: devicons loaded (ft=markdown)")
		end,
	},
	-- Lazy-load on VeryLazy + keymap
	{
		dir = plugin_dir .. "/which-key.nvim",
		event = "VeryLazy",
		keys = "<leader>wk",
		config = function()
			print("E2E: which-key loaded")
			require("which-key").setup({})
		end,
	},
	-- Lazy-load on command
	{
		dir = plugin_dir .. "/oil.nvim",
		cmd = "Oil",
		keys = { { lhs = "<leader>o", mode = { "n" } } },
		config = function()
			print("E2E: oil loaded")
			require("oil").setup({})
		end,
	},
	-- Module-triggered load (nui has nui.popup, nui.layout, etc.)
	{
		dir = plugin_dir .. "/nui.nvim",
		module = "nui.popup",
		config = function()
			print("E2E: nui module-loaded")
		end,
	},
}

local compiled = laze.compile(specs)
vim.pack.add(compiled.pack)
local timings = {}
local plan = laze.build_plan(compiled, {
	on_load = function(id, ms) table.insert(timings, { id = id, time_ms = ms }) end,
})
plan()

print("E2E: setup complete")

-- Trigger lazy loads
vim.cmd("edit /tmp/test.md") -- trigger ft=markdown
-- Script mode (-l) skips filetype detection for new buffers: set it
-- explicitly so the ft=markdown trigger fires.
vim.bo.filetype = "markdown"
vim.wait(100)
vim.cmd("Oil") -- trigger cmd=Oil
vim.wait(100)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>wk", true, false, true), "n", false) -- trigger keys
vim.wait(100)
require("nui.popup") -- trigger module
vim.wait(100)

print("E2E: profile:", vim.inspect(timings))
