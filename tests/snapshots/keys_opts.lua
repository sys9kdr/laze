local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "key-plain",
			src = "https://github.com/user/key-plain",
		},
		{
			name = "key-desc-silent",
			src = "https://github.com/user/key-desc-silent",
		},
	},
	registry = {
		["key-desc-silent"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "key-desc-silent",
			is_dep = false,
			pkg = "key-desc-silent",
			priority = 50,
			silent = false,
			src = "https://github.com/user/key-desc-silent",
		},
		["key-plain"] = {
			after = {},
			eager = false,
			enabled = true,
			has_route = true,
			id = "key-plain",
			is_dep = false,
			pkg = "key-plain",
			priority = 50,
			silent = false,
			src = "https://github.com/user/key-plain",
		},
	},
	routes = {
		cmds = {},
		events = {},
		fts = {},
		keys = {
			[",,d"] = {
				{
					desc = "my desc",
					ids = {
						"key-desc-silent",
					},
					mode = "n",
					rhs = "<cmd>echo 1<CR>",
					silent = true,
				},
			},
			[",,x"] = {
				{
					ids = {
						"key-plain",
					},
					mode = "n",
				},
			},
		},
		modules = {},
	},
}
