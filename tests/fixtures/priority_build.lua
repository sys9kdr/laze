return {
	specs = {
		{
			"user/colorscheme",
			priority = 100,
		},
		{
			"user/default-plugin",
		},
		{
			"user/low-priority",
			priority = 1,
			event = "VeryLazy",
		},
		{
			"user/no-build",
			build = false,
			event = "VeryLazy",
		},
		{
			"user/build-str",
			build = "make",
			event = "VeryLazy",
		},
		{
			"user/build-fn",
			build = function() end,
			event = "VeryLazy",
		},
	},
}
