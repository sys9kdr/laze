local FN = require("tests.fixtures._sentinel").FN -- luacheck: ignore FN

return {
	pack = {
		{
			name = "custom-id",
			src = "https://github.com/user/plugin-a",
		},
	},
	registry = {
		["custom-id"] = {
			after = {},
			enabled = false,
			has_route = false,
			id = "custom-id",
			is_dep = false,
			pkg = "custom-id",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-a",
		},
	},
	routes = {
		cmds = {},
		events = {},
		fts = {},
		keys = {},
		modules = {},
	},
}
