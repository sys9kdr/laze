local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-a",
			src = "https://github.com/user/plugin-a",
		},
		{
			name = "plugin-b",
			src = "https://github.com/user/plugin-b",
		},
		{
			name = "plugin-c",
			src = "https://github.com/user/plugin-c",
		},
	},
	registry = {
		["plugin-a"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = false,
			id = "plugin-a",
			is_dep = true,
			pkg = "plugin-a",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-a",
		},
		["plugin-b"] = {
			after = {
				"plugin-a",
			},
			eager = false,
			enabled = true,
			has_route = false,
			id = "plugin-b",
			is_dep = true,
			pkg = "plugin-b",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-b",
		},
		["plugin-c"] = {
			after = {
				"plugin-b",
				"plugin-a",
			},
			eager = true,
			enabled = true,
			has_route = false,
			id = "plugin-c",
			is_dep = false,
			pkg = "plugin-c",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-c",
		},
	},
	routes = {
		cmds = {},
		events = {},
		fts = {},
		keys = {},
		modules = {},
	},
}
