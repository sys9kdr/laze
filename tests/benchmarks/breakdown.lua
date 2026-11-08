-- Cold setup breakdown: where does wall time actually go?
-- Fresh process per run; phases are timed back-to-back IN the process, so
-- the deltas are not polluted by the +-100us inter-process noise.
-- Run: nvim --clean -l tests/benchmarks/breakdown.lua   (repo root)
vim.opt.rtp:prepend(vim.uv.cwd())
local uv = vim.uv
local function us(t) return (uv.hrtime() - t) / 1000 end

local n = tonumber(vim.env.N or "50")

local t = uv.hrtime()
require("laze.compile")
local req_compile = us(t)

t = uv.hrtime()
require("laze.plan")
local req_plan = us(t)

t = uv.hrtime()
local laze = require("laze")
local req_init = us(t)

-- realistic mix: event/ft/cmd/keys triggers, some deps/after, no dev
local specs = {}
for i = 1, n do
	local s = { ("user/plugin-%d"):format(i), name = ("p%d"):format(i) }
	if i % 3 == 0 then s.event = "VeryLazy" end
	if i % 5 == 0 then s.ft = { "lua", "vim" } end
	if i % 7 == 0 then s.cmd = { ("Cmd%d"):format(i) } end
	if i % 11 == 0 then s.keys = { { ("<leader>%d"):format(i), "<cmd>do<cr>" } } end
	if i % 13 == 0 then s.after = { ("p%d"):format(i - 1) } end
	if i % 17 == 0 then s.module = ("mod%d"):format(i) end
	if i % 19 == 0 then s.dependencies = ("user/dep-%d"):format(i) end
	specs[i] = s
end

t = uv.hrtime()
local compiled = laze.compile(specs)
local t_compile = us(t)

-- disable everything so plan() only registers (no plugin I/O)
for _, e in pairs(compiled.registry) do e.enabled = false end

t = uv.hrtime()
local plan = laze.build_plan(compiled)
local t_plan_build = us(t)

t = uv.hrtime()
plan()
local t_plan_run = us(t)

print(("N=%d req.compile=%.0fus req.plan=%.0fus req.init=%.0fus compile=%.0fus build_plan=%.0fus plan()=%.0fus"):format(
	n, req_compile, req_plan, req_init, t_compile, t_plan_build, t_plan_run))
