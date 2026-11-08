local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "lazy-default",
			src = "https://github.com/folke/lazy-default.nvim",
		},
		{
			name = "lazy-true",
			src = "https://github.com/folke/lazy-true.nvim",
		},
		{
			name = "lazy-false",
			src = "https://github.com/folke/lazy-false.nvim",
		},
		{
			name = "lazy-child",
			src = "https://github.com/folke/lazy-child.nvim",
		},
		{
			name = "lazy-dep",
			src = "https://github.com/folke/lazy-dep.nvim",
		},
	},
	registry = {
		["lazy-child"] = {
			after = {},
			eager = true,
			enabled = true,
			has_route = false,
			id = "lazy-child",
			is_dep = true,
			lazy = false,
			pkg = "lazy-child",
			priority = 50,
			silent = false,
			src = "https://github.com/folke/lazy-child.nvim",
		},
		["lazy-default"] = {
			after = {},
			eager = true,
			enabled = true,
			has_route = false,
			id = "lazy-default",
			is_dep = false,
			pkg = "lazy-default",
			priority = 50,
			silent = false,
			src = "https://github.com/folke/lazy-default.nvim",
		},
		["lazy-dep"] = {
			after = {
				"lazy-child",
			},
			eager = true,
			enabled = true,
			has_route = false,
			id = "lazy-dep",
			is_dep = false,
			pkg = "lazy-dep",
			priority = 50,
			silent = false,
			src = "https://github.com/folke/lazy-dep.nvim",
		},
		["lazy-false"] = {
			after = {},
			eager = true,
			enabled = true,
			has_route = true,
			id = "lazy-false",
			is_dep = false,
			lazy = false,
			pkg = "lazy-false",
			priority = 50,
			silent = false,
			src = "https://github.com/folke/lazy-false.nvim",
		},
		["lazy-true"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = false,
			id = "lazy-true",
			is_dep = false,
			lazy = true,
			pkg = "lazy-true",
			priority = 50,
			silent = false,
			src = "https://github.com/folke/lazy-true.nvim",
		},
	},
	routes = {
		cmds = {},
		events = {
			BufReadPost = {
				{
					ids = {
						"lazy-false",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
