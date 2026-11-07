--- Compile-time notifications for known differences (issue #12).
---
--- Only entries with `notify = "compile"` in docs/known-differences.md are
--- surfaced here; `notify = "never"` entries stay docs-only. The message
--- names the stable ID and the docs path so a user can look up the exact
--- conversion.
---
--- Messages are deduped per compile by the caller (a single vim.notify
--- costs ~180 us headless, so N occurrences must not pay N×), and the whole
--- group is opt-out with `compile(specs, { known_differences = false })`.
local M = {}

M.docs = "docs/known-differences.md"

--- Short descriptions for each `notify = "compile"` entry. Longer context
--- belongs in the docs; the runtime message stays one line.
M.entries = {
	["KD-016"] = "unsupported key options are dropped",
	["KD-020"] = "field has no laze equivalent",
}

---@param id string Stable KD id (e.g. "KD-016").
---@param detail string One-line, caller-provided detail.
---@param notified? table<string, boolean> Per-compile dedupe table.
---@param opts? { known_differences?: boolean } Compile options.
---@param key? string Dedupe key when one ID covers several distinct cases.
function M.notify(id, detail, notified, opts, key)
	if opts and opts.known_differences == false then
		return
	end
	key = key or id
	if notified then
		if notified[key] then
			return
		end
		notified[key] = true
	end
	vim.notify(("laze: %s (%s, see %s)"):format(detail, id, M.docs), vim.log.levels.WARN)
end

return M
