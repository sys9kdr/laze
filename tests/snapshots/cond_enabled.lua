local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-cond-false",
			src = "https://github.com/user/plugin-cond-false",
		},
		{
			name = "plugin-cond-true",
			src = "https://github.com/user/plugin-cond-true",
		},
		{
			name = "plugin-enabled-fn",
			src = "https://github.com/user/plugin-enabled-fn",
		},
		{
			name = "plugin-module-false",
			src = "https://github.com/user/plugin-module-false",
		},
		{
			name = "plugin-priority",
			src = "https://github.com/user/plugin-priority",
		},
	},
	registry = {
		["plugin-cond-false"] = {
			after = {},
			cond = false,
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
			cond = true,
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
		["plugin-enabled-fn"] = {
			after = {},
			eager = false,
			enabled = FN,
			has_route = true,
			id = "plugin-enabled-fn",
			is_dep = false,
			pkg = "plugin-enabled-fn",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-enabled-fn",
		},
		["plugin-module-false"] = {
			after = {},
			eager = true,
			enabled = true,
			has_route = false,
			id = "plugin-module-false",
			is_dep = false,
			module = false,
			pkg = "plugin-module-false",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-module-false",
		},
		["plugin-priority"] = {
			after = {},
			eager = true,
			enabled = true,
			has_route = false,
			id = "plugin-priority",
			is_dep = false,
			pkg = "plugin-priority",
			priority = 1000,
			silent = false,
			src = "https://github.com/user/plugin-priority",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"plugin-cond-false",
						"plugin-cond-true",
						"plugin-enabled-fn",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
