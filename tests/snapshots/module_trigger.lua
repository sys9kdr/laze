local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-module",
			src = "https://github.com/user/plugin-module",
		},
		{
			name = "plugin-module-array",
			src = "https://github.com/user/plugin-module-array",
		},
	},
	registry = {
		["plugin-module"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "plugin-module",
			is_dep = false,
			module = "my-plugin",
			pkg = "plugin-module",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-module",
		},
		["plugin-module-array"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "plugin-module-array",
			is_dep = false,
			module = {
				"my-plugin-a",
				"my-plugin-b",
			},
			pkg = "plugin-module-array",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-module-array",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"plugin-module",
						"plugin-module-array",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {
			["my-plugin"] = {
				"plugin-module",
			},
			["my-plugin-a"] = {
				"plugin-module-array",
			},
			["my-plugin-b"] = {
				"plugin-module-array",
			},
		},
	},
}
