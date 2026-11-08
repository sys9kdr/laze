local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "only-dep1",
			src = "https://github.com/user/only-dep1",
		},
		{
			name = "parent1",
			src = "https://github.com/user/parent1",
		},
		{
			name = "parent2",
			src = "https://github.com/user/parent2",
		},
		{
			name = "shared-dep",
			src = "https://github.com/user/shared-dep",
		},
	},
	registry = {
		["only-dep1"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = false,
			id = "only-dep1",
			is_dep = true,
			pkg = "only-dep1",
			priority = 50,
			silent = false,
			src = "https://github.com/user/only-dep1",
		},
		parent1 = {
			after = {
				"shared-dep",
				"only-dep1",
			},
			eager = false,
			enabled = true,
			has_route = true,
			id = "parent1",
			is_dep = false,
			pkg = "parent1",
			priority = 50,
			silent = false,
			src = "https://github.com/user/parent1",
		},
		parent2 = {
			after = {
				"shared-dep",
			},
			eager = false,
			enabled = true,
			has_route = true,
			id = "parent2",
			is_dep = false,
			pkg = "parent2",
			priority = 50,
			silent = false,
			src = "https://github.com/user/parent2",
		},
		["shared-dep"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "shared-dep",
			is_dep = true,
			pkg = "shared-dep",
			priority = 50,
			silent = false,
			src = "https://github.com/user/shared-dep",
		},
	},
	routes = {
		cmds = {
			SharedDepCmd = {
				"shared-dep",
			},
		},
		events = {
			VeryLazy = {
				{
					ids = {
						"parent1",
						"parent2",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
