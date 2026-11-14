--- Error and notify formatting, kept out of the hot modules: call sites use an inline require, so this parses only when
--- a message fires. The message bytes are the contract (tests substring-match them).
local M = {}

---@param msg string
function M.warn(msg)
	vim.notify("laze: " .. msg, vim.log.levels.WARN)
end

--- Emit the diagnostics returned by compile. The functional core collects them; the shell notifies.
---@param diagnostics LazeDiagnostic[]
function M.flush(diagnostics)
	for _, d in ipairs(diagnostics or {}) do
		if d.id then
			vim.notify(require("laze.internal.known_differences").format(d.id, d.detail), vim.log.levels.WARN)
		elseif d.message then
			M.warn(d.message)
		end
	end
end

function M.spec(idx, spec_id, msg)
	error(("spec [%d] (%s): %s"):format(idx, spec_id, msg), 0)
end

--- Error raised before the spec id is known.
function M.spec_at(idx, msg)
	error(("spec [%d]: %s"):format(idx, msg), 0)
end

function M.bad(idx, spec_id, field, msg)
	error(("spec [%d] (%s): %s %s"):format(idx, spec_id, field, msg), 0)
end

return M
