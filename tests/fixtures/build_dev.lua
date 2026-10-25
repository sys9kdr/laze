return {
	-- Fixed dev root so the snapshot does not depend on $HOME (the
	-- default "~/dev" would bake the machine's home directory into it).
	opts = { dev_root = "/home/user/dev" },
	specs = {
		{
			"user/plugin-build",
			build = ":TSUpdate",
			event = "VeryLazy",
		},
		{
			"user/plugin-build-fn",
			build = function()
				print("building...")
			end,
			event = "VeryLazy",
		},
		{
			"user/plugin-dev",
			dev = true,
			dev_path = "~/dev/my-plugin",
			event = "VeryLazy",
		},
	},
}
