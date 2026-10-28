local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "repo",
			src = "https://github.com/user/repo.git",
		},
		{
			name = "plugin",
			src = "https://github.com/user/plugin/",
		},
		{
			name = "which-key.nvim",
			src = "https://github.com/folke/which-key.nvim",
		},
		{
			name = "lua-src.lua",
			src = "https://github.com/user/lua-src.lua",
		},
	},
	registry = {
		["lua-src"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "lua-src",
			is_dep = false,
			pkg = "lua-src.lua",
			priority = 50,
			silent = false,
			src = "https://github.com/user/lua-src.lua",
		},
		plugin = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin",
			is_dep = false,
			pkg = "plugin",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin/",
		},
		repo = {
			after = {},
			enabled = true,
			has_route = true,
			id = "repo",
			is_dep = false,
			pkg = "repo",
			priority = 50,
			silent = false,
			src = "https://github.com/user/repo.git",
		},
		["which-key"] = {
			after = {},
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
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"repo",
						"plugin",
						"which-key",
						"lua-src",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
