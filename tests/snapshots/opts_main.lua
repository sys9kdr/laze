local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "opts-plugin",
			src = "https://github.com/user/opts-plugin",
		},
		{
			name = "opts-eager",
			src = "https://github.com/user/opts-eager",
		},
	},
	registry = {
		["opts-eager"] = {
			after = {},
			config = FN,
			enabled = true,
			has_route = false,
			id = "opts-eager",
			is_dep = false,
			main = "opts_eager_mod",
			opts = {
				bar = "x",
			},
			pkg = "opts-eager",
			priority = 50,
			silent = false,
			src = "https://github.com/user/opts-eager",
		},
		["opts-plugin"] = {
			after = {},
			config = FN,
			enabled = true,
			has_route = true,
			id = "opts-plugin",
			is_dep = false,
			main = "opts_plugin_mod",
			opts = {
				foo = 1,
				nested = {
					a = true,
				},
			},
			pkg = "opts-plugin",
			priority = 50,
			silent = false,
			src = "https://github.com/user/opts-plugin",
		},
	},
	routes = {
		cmds = {},
		events = {
			BufReadPost = {
				{
					ids = {
						"opts-plugin",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
