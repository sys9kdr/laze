return {
	specs = {
		{ "folke/lazy-default.nvim", name = "lazy-default" },
		{ "folke/lazy-true.nvim", name = "lazy-true", lazy = true },
		{ "folke/lazy-false.nvim", name = "lazy-false", event = "BufRead", lazy = false },
		{
			"folke/lazy-dep.nvim",
			name = "lazy-dep",
			dependencies = {
				{ "folke/lazy-child.nvim", name = "lazy-child", lazy = false },
			},
		},
	},
}
