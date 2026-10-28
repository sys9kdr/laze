return {
	specs = {
		{
			"user/plugin-simple",
			event = "BufReadPre",
		},
		{
			"user/plugin-pattern",
			event = { event = "BufWritePost", pattern = "*.lua" },
		},
		{
			"user/plugin-array",
			event = { "BufEnter", { event = "BufLeave", pattern = "*.md" } },
		},
		-- Same event as plugin-simple, different pattern: routes independently.
		{
			"user/plugin-same-event",
			event = { { event = "BufReadPre", pattern = "*.lua" } },
		},
		-- Same (event, pattern) pair via the single-table form: deduped into
		-- the same variant as plugin-same-event.
		{
			"user/plugin-same-event-dedup",
			event = { event = "BufReadPre", pattern = "*.lua" },
		},
	},
}
