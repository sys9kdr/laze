local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "myplugin",
			src = "/tmp/laze-test/myplugin",
		},
		{
			name = "plugin",
			src = "/custom/path/to/plugin",
		},
	},
	registry = {
		myplugin = {
			after = {},
			dev = "/tmp/laze-test/myplugin",
			enabled = true,
			has_route = true,
			id = "myplugin",
			is_dep = false,
			pkg = "myplugin",
			priority = 50,
			silent = false,
			src = "/tmp/laze-test/myplugin",
		},
		plugin = {
			after = {},
			dev = "/custom/path/to/plugin",
			enabled = true,
			has_route = true,
			id = "plugin",
			is_dep = false,
			pkg = "plugin",
			priority = 50,
			silent = false,
			src = "/custom/path/to/plugin",
		},
	},
	routes = {
		cmds = {},
		events = {},
		fts = {},
		keys = {
			["<leader>a"] = {
				{
					ids = {
						"plugin",
					},
					mode = "n",
				},
			},
			["<leader>b"] = {
				{
					ids = {
						"plugin",
					},
					mode = "n",
				},
			},
			["<leader>ff"] = {
				{
					ids = {
						"myplugin",
					},
					mode = "n",
				},
			},
		},
		modules = {},
	},
}
