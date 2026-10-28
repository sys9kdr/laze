local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "wk",
			src = "https://github.com/folke/which-key.nvim",
		},
	},
	registry = {
		wk = {
			after = {},
			enabled = true,
			has_route = true,
			id = "wk",
			is_dep = false,
			pkg = "wk",
			priority = 50,
			silent = false,
			src = "https://github.com/folke/which-key.nvim",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"wk",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
