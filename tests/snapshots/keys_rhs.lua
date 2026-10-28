local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "keys-rhs-fn",
			src = "https://github.com/user/keys-rhs-fn",
		},
		{
			name = "keys-rhs-str",
			src = "https://github.com/user/keys-rhs-str",
		},
		{
			name = "keys-mixed",
			src = "https://github.com/user/keys-mixed",
		},
	},
	registry = {
		["keys-mixed"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "keys-mixed",
			is_dep = false,
			pkg = "keys-mixed",
			priority = 50,
			silent = false,
			src = "https://github.com/user/keys-mixed",
		},
		["keys-rhs-fn"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "keys-rhs-fn",
			is_dep = false,
			pkg = "keys-rhs-fn",
			priority = 50,
			silent = false,
			src = "https://github.com/user/keys-rhs-fn",
		},
		["keys-rhs-str"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "keys-rhs-str",
			is_dep = false,
			pkg = "keys-rhs-str",
			priority = 50,
			silent = false,
			src = "https://github.com/user/keys-rhs-str",
		},
	},
	routes = {
		cmds = {},
		events = {},
		fts = {},
		keys = {
			[",,dv"] = {
				{
					ids = {
						"keys-rhs-str",
					},
					mode = "n",
					rhs = ":DiffviewOpen<CR>",
				},
			},
			[",,gb"] = {
				{
					ids = {
						"keys-rhs-fn",
					},
					mode = "n",
					rhs = FN,
				},
			},
			[",,o"] = {
				{
					ids = {
						"keys-rhs-fn",
					},
					mode = "n",
					rhs = FN,
				},
			},
			[",,x"] = {
				{
					ids = {
						"keys-mixed",
					},
					mode = "v",
				},
			},
			["<leader>a"] = {
				{
					ids = {
						"keys-mixed",
					},
					mode = "n",
				},
			},
		},
		modules = {},
	},
}
