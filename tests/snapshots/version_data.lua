local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-version",
			src = "https://github.com/user/plugin-version",
			version = "v1.0.0",
		},
		{
			data = {
				custom = "data",
				value = 42,
			},
			name = "plugin-data",
			src = "https://github.com/user/plugin-data",
		},
		{
			data = {
				key = "value",
			},
			name = "plugin-both",
			src = "https://github.com/user/plugin-both",
			version = "main",
		},
	},
	registry = {
		["plugin-both"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-both",
			is_dep = false,
			pkg = "plugin-both",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-both",
		},
		["plugin-data"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-data",
			is_dep = false,
			pkg = "plugin-data",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-data",
		},
		["plugin-version"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-version",
			is_dep = false,
			pkg = "plugin-version",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-version",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"plugin-version",
						"plugin-data",
						"plugin-both",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
