-- Probe template: measure actual lazy.nvim state for a handful of specs.
--
--   LAZY_DIR=/path/to/lazy.nvim nvim --headless -u NONE -l probe.lua
--
-- Replace the add() calls with the spec shapes under question. Each case gets
-- a unique dir on purpose: lazy indexes plugins by dir (Meta.str_to_meta), so
-- sharing one dir would merge all cases into a single plugin.
vim.go.loadplugins = true -- `nvim -l` disables it; setup() would return silently

local lazy_dir = vim.env.LAZY_DIR
if not lazy_dir or lazy_dir == "" then
	error("set LAZY_DIR to a lazy.nvim checkout")
end
vim.opt.rtp:prepend(lazy_dir)

local Config = require("lazy.core.config")
local Keys = require("lazy.core.handler.keys")

local root = "/tmp/opencode/lazy-probe"
local specs = {}

---@param name string
---@param spec? table
local function add(name, spec)
	spec = spec or {}
	spec.name = name
	spec.dir = root .. "/" .. name
	vim.fn.mkdir(spec.dir, "p")
	specs[#specs + 1] = spec
end

add("keys-false", { keys = { { "<F9>", false } } })
add("keys-real", { keys = { { "<F9>", "x" } } })
-- add("keys-vim-nil", { keys = { { "<F9>", vim.NIL } } })
-- add("event", { event = "BufRead" })
-- add("lazy-true", { lazy = true })

require("lazy").setup({
	spec = specs,
	install = { missing = false },
	checker = { enabled = false },
})

for _, spec in ipairs(specs) do
	local plugin = Config.plugins[spec.name]
	local raw = plugin and plugin.keys
	local resolved = {}
	if type(raw) == "table" then
		-- Keys.resolve takes an array; the real path wraps a bare string via
		-- Plugin.values(plugin, "keys", true) before calling it.
		local ok, value = pcall(Keys.resolve, raw)
		if ok then
			resolved = value
		end
	end
	local ids = {}
	for id in pairs(resolved) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	local handlers = plugin and plugin._ and plugin._.handlers and plugin._.handlers.keys
	local handler_n = 0
	for _ in pairs(handlers or {}) do
		handler_n = handler_n + 1
	end
	print(
		("[%s] lazy=%s keys_type=%s raw_n=%s resolved=%d handlers=%d {%s}"):format(
			spec.name,
			tostring(plugin and plugin.lazy),
			type(raw),
			type(raw) == "table" and #raw or "-",
			#ids,
			handler_n,
			table.concat(ids, ",")
		)
	)
end
