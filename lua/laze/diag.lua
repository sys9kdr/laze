--- Error and notify formatting, kept out of the hot modules: call sites use
--- an inline require, so this parses only when a message fires. The message
--- bytes are the contract (tests substring-match them).
local M = {}

--- Warn with the standard "laze: " prefix.
---@param msg string
function M.warn(msg)
	vim.notify("laze: " .. msg, vim.log.levels.WARN)
end

--- Spec-scoped error, shape `spec [3] (owner/repo): msg`.
function M.spec(idx, spec_id, msg)
	error(("spec [%d] (%s): %s"):format(idx, spec_id, msg), 0)
end

--- Error raised before the spec id is known, shape `spec [3]: msg`.
function M.spec_at(idx, msg)
	error(("spec [%d]: %s"):format(idx, msg), 0)
end

--- Field-scoped error, shape `spec [3] (owner/repo): field msg`.
function M.bad(idx, spec_id, field, msg)
	error(("spec [%d] (%s): %s %s"):format(idx, spec_id, field, msg), 0)
end

return M
