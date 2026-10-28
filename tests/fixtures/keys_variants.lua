return {
	specs = {
		{
			"user/key-both",
			keys = {
				{ lhs = ",,x", mode = "n", rhs = "<cmd>N<CR>" },
				{ lhs = ",,x", mode = "v", rhs = "<cmd>V<CR>" },
				{ lhs = ",,m", mode = { "n", "v", "x" } },
			},
		},
		{
			-- Same lhs as key-both, different mode: must get its own variant.
			"user/key-i",
			keys = { { lhs = ",,x", mode = "i", rhs = "<cmd>I<CR>" } },
		},
		{
			-- Same lhs + same mode + same opts as key-both's v variant:
			-- shared trigger, both ids load.
			"user/key-v-shared",
			keys = { { lhs = ",,x", mode = "v", rhs = "<cmd>V<CR>" } },
		},
	},
}
