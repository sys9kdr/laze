local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-branch",
			src = "https://github.com/user/plugin-branch",
			version = "develop",
		},
		{
			name = "plugin-tag",
			src = "https://github.com/user/plugin-tag",
			version = "v1.0.0",
		},
		{
			name = "plugin-commit",
			src = "https://github.com/user/plugin-commit",
			version = "abc123",
		},
		{
			name = "plugin-pin",
			pin = true,
			src = "https://github.com/user/plugin-pin",
		},
		{
			name = "plugin-multiple",
			pin = false,
			src = "https://github.com/user/plugin-multiple",
			version = "def456",
		},
	},
	registry = {
		["plugin-branch"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-branch",
			is_dep = false,
			pkg = "plugin-branch",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-branch",
		},
		["plugin-commit"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-commit",
			is_dep = false,
			pkg = "plugin-commit",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-commit",
		},
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
		["plugin-tag"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-tag",
			is_dep = false,
			pkg = "plugin-tag",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-tag",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"plugin-branch",
						"plugin-tag",
						"plugin-commit",
						"plugin-pin",
						"plugin-multiple",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
