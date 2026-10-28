local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "which-key.nvim",
			src = "https://github.com/folke/which-key.nvim",
		},
		{
			name = "nvim-treesitter",
			src = "https://github.com/nvim-treesitter/nvim-treesitter",
		},
		{
			name = "oil.nvim",
			src = "https://github.com/stevearc/oil.nvim",
		},
	},
	registry = {
		["nvim-treesitter"] = {
			after = {},
			config = FN,
			enabled = true,
			has_route = true,
			id = "nvim-treesitter",
			is_dep = false,
			pkg = "nvim-treesitter",
			priority = 50,
			silent = false,
			src = "https://github.com/nvim-treesitter/nvim-treesitter",
		},
		oil = {
			after = {},
			config = FN,
			enabled = true,
			has_route = true,
			id = "oil",
			is_dep = false,
			pkg = "oil.nvim",
			priority = 50,
			silent = false,
			src = "https://github.com/stevearc/oil.nvim",
		},
		["which-key"] = {
			after = {},
			config = FN,
			enabled = true,
			has_route = true,
			id = "which-key",
			is_dep = false,
			pkg = "which-key.nvim",
			priority = 50,
			silent = false,
			src = "https://github.com/folke/which-key.nvim",
		},
	},
	routes = {
		cmds = {
			Oil = {
				"oil",
			},
		},
		events = {
			VeryLazy = {
				{
					ids = {
						"which-key",
					},
				},
			},
		},
		fts = {
			lua = {
				"nvim-treesitter",
			},
			vim = {
				"nvim-treesitter",
			},
		},
		keys = {},
		modules = {},
	},
}
