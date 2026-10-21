local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-pin",
			pin = true,
			src = "https://github.com/user/plugin-pin",
		},
		{
			name = "plugin-multiple",
			pin = false,
			src = "https://github.com/user/plugin-multiple",
		},
	},
	registry = {
		["plugin-multiple"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-multiple",
			is_dep = false,
			pkg = "plugin-multiple",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-multiple",
		},
		["plugin-pin"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-pin",
			is_dep = false,
			pkg = "plugin-pin",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-pin",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				ids = {
					"plugin-pin",
					"plugin-multiple",
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
