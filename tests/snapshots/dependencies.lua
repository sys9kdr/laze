local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-dep1",
			src = "https://github.com/user/plugin-dep1",
		},
		{
			name = "dep2-custom",
			src = "https://github.com/user/plugin-dep2",
		},
		{
			name = "plugin-main",
			src = "https://github.com/user/plugin-main",
		},
	},
	registry = {
		["dep2-custom"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = false,
			id = "dep2-custom",
			is_dep = true,
			pkg = "dep2-custom",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-dep2",
		},
		["plugin-dep1"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = false,
			id = "plugin-dep1",
			is_dep = true,
			pkg = "plugin-dep1",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-dep1",
		},
		["plugin-main"] = {
			after = {
				"plugin-dep1",
				"dep2-custom",
			},
			eager = true,
			enabled = true,
			has_route = false,
			id = "plugin-main",
			is_dep = false,
			pkg = "plugin-main",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-main",
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
