local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-silent",
			src = "https://github.com/user/plugin-silent",
		},
		{
			name = "plugin-noisy",
			src = "https://github.com/user/plugin-noisy",
		},
	},
	registry = {
		["plugin-noisy"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-noisy",
			is_dep = false,
			pkg = "plugin-noisy",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-noisy",
		},
		["plugin-silent"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-silent",
			is_dep = false,
			pkg = "plugin-silent",
			priority = 50,
			silent = true,
			src = "https://github.com/user/plugin-silent",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"plugin-silent",
						"plugin-noisy",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
