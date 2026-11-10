vim.loader.enable()

local laze = require("laze")
local plugin_dir = vim.env.LAZE_PLUGINS or "/tmp/laze-plugins"

local specs = {
	{
		dir = plugin_dir .. "/plenary.nvim",
		config = function()
			print("laze-test: plenary loaded")
		end,
	},

	-- One spec per id: ft and module both stay lazy and each fires the same load.
	{
		dir = plugin_dir .. "/nui.nvim",
		ft = "markdown",
		module = "nui.popup",
		config = function()
			print("laze-test: nui loaded (ft=markdown / module=nui.popup)")
		end,
	},

	{
		dir = plugin_dir .. "/which-key.nvim",
		event = "VeryLazy",
		keys = "<leader>wk",
		config = function()
			print("laze-test: which-key loaded")
			require("which-key").setup({})
		end,
	},

	{
		dir = plugin_dir .. "/oil.nvim",
		cmd = "Oil",
		keys = { { lhs = "<leader>o", mode = { "n" } } },
		config = function()
			print("laze-test: oil loaded")
			require("oil").setup({})
		end,
	},

	-- Set g:laze_test_cond=false and restart to observe the skip.
	{
		dir = plugin_dir .. "/nvim-web-devicons",
		cond = function()
			return vim.g.laze_test_cond ~= false
		end,
		config = function()
			print("laze-test: devicons loaded (cond)")
		end,
	},
}

local compiled = laze.compile(specs)
vim.pack.add(compiled.pack)
local plan = laze.build_plan(compiled)
plan()

print("laze-test: setup complete")
print("  try: :edit test.md              -> ft trigger (nui)")
print("  try: :lua require('nui.popup')  -> module trigger (nui)")
print("  try: :Oil                       -> cmd trigger (oil)")
print("  try: <leader>wk                 -> keys trigger (which-key)")
print("  try: <leader>o                  -> keys trigger (oil)")
