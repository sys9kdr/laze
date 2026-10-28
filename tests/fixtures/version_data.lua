return {
	specs = {
		{
			"user/plugin-version",
			tag = "v1.0.0",
			event = "VeryLazy",
		},
		{
			"user/plugin-data",
			data = { custom = "data", value = 42 },
			event = "VeryLazy",
		},
		{
			"user/plugin-both",
			branch = "main",
			data = { key = "value" },
			event = "VeryLazy",
		},
	},
}
