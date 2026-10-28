local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-simple",
			src = "https://github.com/user/plugin-simple",
		},
		{
			name = "plugin-pattern",
			src = "https://github.com/user/plugin-pattern",
		},
		{
			name = "plugin-array",
			src = "https://github.com/user/plugin-array",
		},
		{
			name = "plugin-same-event",
			src = "https://github.com/user/plugin-same-event",
		},
		{
			name = "plugin-same-event-dedup",
			src = "https://github.com/user/plugin-same-event-dedup",
		},
	},
	registry = {
		["plugin-array"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-array",
			is_dep = false,
			pkg = "plugin-array",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-array",
		},
		["plugin-pattern"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-pattern",
			is_dep = false,
			pkg = "plugin-pattern",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-pattern",
		},
		["plugin-same-event"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-same-event",
			is_dep = false,
			pkg = "plugin-same-event",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-same-event",
		},
		["plugin-same-event-dedup"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-same-event-dedup",
			is_dep = false,
			pkg = "plugin-same-event-dedup",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-same-event-dedup",
		},
		["plugin-simple"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-simple",
			is_dep = false,
			pkg = "plugin-simple",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-simple",
		},
	},
	routes = {
		cmds = {},
		events = {
			BufEnter = {
				{
					ids = {
						"plugin-array",
					},
				},
			},
			BufLeave = {
				{
					ids = {
						"plugin-array",
					},
					pattern = "*.md",
				},
			},
			BufReadPre = {
				{
					ids = {
						"plugin-simple",
					},
				},
				{
					ids = {
						"plugin-same-event",
						"plugin-same-event-dedup",
					},
					pattern = "*.lua",
				},
			},
			BufWritePost = {
				{
					ids = {
						"plugin-pattern",
					},
					pattern = "*.lua",
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
