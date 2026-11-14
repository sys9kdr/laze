--- Compile-time notifications for known differences (issue #12). The registry lives in
--- tests/fixtures/known_differences.lua; docs/known-differences.md defines the classes and policy.
---
--- Compile returns KD diagnostics as data; the shell formats and emits them with `format`.
local M = {}

M.docs = "docs/known-differences.md"

---@param id string Stable KD id (e.g. "KD-016").
---@param detail string One-line, caller-provided detail.
---@return string
function M.format(id, detail)
	return ("laze: %s (%s, see %s)"):format(detail, id, M.docs)
end

return M
