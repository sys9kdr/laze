local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "key-both",
			src = "https://github.com/user/key-both",
		},
		{
			name = "key-i",
			src = "https://github.com/user/key-i",
		},
		{
			name = "key-v-shared",
			src = "https://github.com/user/key-v-shared",
		},
	},
	registry = {
		["key-both"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "key-both",
			is_dep = false,
			pkg = "key-both",
			priority = 50,
			silent = false,
			src = "https://github.com/user/key-both",
		},
		["key-i"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "key-i",
			is_dep = false,
			pkg = "key-i",
			priority = 50,
			silent = false,
			src = "https://github.com/user/key-i",
		},
		["key-v-shared"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "key-v-shared",
			is_dep = false,
			pkg = "key-v-shared",
			priority = 50,
			silent = false,
			src = "https://github.com/user/key-v-shared",
		},
	},
	routes = {
		cmds = {},
		events = {},
		fts = {},
		keys = {
			[",,m"] = {
				{
					ids = {
						"key-both",
					},
					mode = "n",
				},
				{
					ids = {
						"key-both",
					},
					mode = "v",
				},
				{
					ids = {
						"key-both",
					},
					mode = "x",
				},
			},
			[",,x"] = {
				{
					ids = {
						"key-both",
					},
					mode = "n",
					rhs = "<cmd>N<CR>",
				},
				{
					ids = {
						"key-both",
						"key-v-shared",
					},
					mode = "v",
					rhs = "<cmd>V<CR>",
				},
				{
					ids = {
						"key-i",
					},
					mode = "i",
					rhs = "<cmd>I<CR>",
				},
			},
		},
		modules = {},
	},
}
