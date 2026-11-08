local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-always",
			src = "https://github.com/user/plugin-always",
		},
		{
			name = "plugin-cond-false",
			src = "https://github.com/user/plugin-cond-false",
		},
		{
			name = "plugin-cond-true",
			src = "https://github.com/user/plugin-cond-true",
		},
	},
	registry = {
		["plugin-always"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "plugin-always",
			is_dep = false,
			pkg = "plugin-always",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-always",
		},
		["plugin-cond-false"] = {
			after = {},
			cond = FN,
			eager = false,
			enabled = true,
			has_route = true,
			id = "plugin-cond-false",
			is_dep = false,
			pkg = "plugin-cond-false",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-cond-false",
		},
		["plugin-cond-true"] = {
			after = {},
			cond = FN,
			eager = false,
			enabled = true,
			has_route = true,
			id = "plugin-cond-true",
			is_dep = false,
			pkg = "plugin-cond-true",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-cond-true",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"plugin-always",
						"plugin-cond-false",
						"plugin-cond-true",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
