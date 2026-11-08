local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "other-plugin",
			src = "/tmp/other-plugin",
		},
		{
			name = "plugin.nvim",
			src = "https://gitlab.com/third/plugin.nvim",
		},
	},
	registry = {
		["my-plugin"] = {
			after = {},
			dir = "/home/user/projects/my-plugin",
			eager = false,
			enabled = true,
			has_route = true,
			id = "my-plugin",
			is_dep = false,
			priority = 50,
			silent = false,
			src = "/home/user/projects/my-plugin",
		},
		["no-name"] = {
			after = {},
			dir = "/home/user/projects/no-name",
			eager = true,
			enabled = true,
			has_route = false,
			id = "no-name",
			is_dep = false,
			priority = 50,
			silent = false,
			src = "/home/user/projects/no-name",
		},
		["other-plugin"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "other-plugin",
			is_dep = false,
			pkg = "other-plugin",
			priority = 50,
			silent = false,
			src = "/tmp/other-plugin",
		},
		plugin = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "plugin",
			is_dep = false,
			pkg = "plugin.nvim",
			priority = 50,
			silent = false,
			src = "https://gitlab.com/third/plugin.nvim",
		},
	},
	routes = {
		cmds = {
			Other = {
				"other-plugin",
			},
		},
		events = {
			BufReadPost = {
				{
					ids = {
						"plugin",
					},
				},
			},
		},
		fts = {},
		keys = {
			["<leader>p"] = {
				{
					ids = {
						"my-plugin",
					},
					mode = "n",
				},
			},
		},
		modules = {},
	},
}
