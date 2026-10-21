return {
	specs = {
		{
			"user/plugin-version",
			version = "v1.0.0",
			event = "VeryLazy",
		},
		{
			"user/plugin-data",
			data = { custom = "data", value = 42 },
			event = "VeryLazy",
		},
		{
			"user/plugin-both",
			version = { from = "1.0.0", to = "2.0.0" },
			data = { key = "value" },
			event = "VeryLazy",
		},
	},
}
