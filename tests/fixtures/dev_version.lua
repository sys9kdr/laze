--- dev + version/refs: an active dev path is a local checkout, so laze must
--- not lower version/branch/tag/commit into the pack entry (lazy.nvim turns
--- `dev` into a local `dir`; vim.pack would otherwise clone the dev path and
--- check out the ref there). The remote spec shows normal lowering is intact.
return {
	-- Fixed dev root so the snapshot does not depend on $HOME.
	opts = { dev_root = "/home/user/dev" },
	specs = {
		{
			"user/plugin-dev-bool",
			dev = true,
			version = ">=1.0.0",
			event = "VeryLazy",
		},
		{
			"user/plugin-dev-path",
			dev = "/home/user/work/plugin-dev-path",
			version = "^2.0.0",
			event = "VeryLazy",
		},
		{
			"user/plugin-dev-fallback",
			dev_path = "/home/user/work/plugin-dev-fallback",
			version = "1.2.3",
			event = "VeryLazy",
		},
		{
			"user/plugin-dev-tag",
			dev = true,
			tag = "v1.0.0",
			event = "VeryLazy",
		},
		{
			"user/plugin-dev-commit",
			dev = true,
			commit = "abc123",
			event = "VeryLazy",
		},
		{
			"user/plugin-dev-branch",
			dev = true,
			branch = "develop",
			event = "VeryLazy",
		},
		{
			"user/plugin-remote-tag",
			tag = "v1.0.0",
			version = ">=2.0.0",
			event = "VeryLazy",
		},
	},
}
