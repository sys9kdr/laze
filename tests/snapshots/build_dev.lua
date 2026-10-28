local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			build = ":TSUpdate",
			name = "plugin-build",
			src = "https://github.com/user/plugin-build",
		},
		{
			build = FN,
			name = "plugin-build-fn",
			src = "https://github.com/user/plugin-build-fn",
		},
		{
			name = "plugin-dev",
			src = "/home/user/dev/plugin-dev",
		},
	},
	registry = {
		["plugin-build"] = {
			after = {},
			build = ":TSUpdate",
			enabled = true,
			has_route = true,
			id = "plugin-build",
			is_dep = false,
			pkg = "plugin-build",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-build",
		},
		["plugin-build-fn"] = {
			after = {},
			build = FN,
			enabled = true,
			has_route = true,
			id = "plugin-build-fn",
			is_dep = false,
			pkg = "plugin-build-fn",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-build-fn",
		},
		["plugin-dev"] = {
			after = {},
			dev = true,
			dev_path = "~/dev/my-plugin",
			enabled = true,
			has_route = true,
			id = "plugin-dev",
			is_dep = false,
			pkg = "plugin-dev",
			priority = 50,
			silent = false,
			src = "/home/user/dev/plugin-dev",
		},
	},
	routes = {
		cmds = {},
		events = {
			VeryLazy = {
				{
					ids = {
						"plugin-build",
						"plugin-build-fn",
						"plugin-dev",
					},
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
