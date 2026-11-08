-- Fresh-process JIT A/B oracle. Not part of CI: run it before proposing or
-- believing a "this stays on the JIT" claim, and re-run after engine bumps.
--
-- Why a stopwatch and not a tracer: this build (LuaJIT 2.1.1793383622 — the
-- rewritten engine shipped by Neovim 0.12.6) has NO jit.util, jit.dump,
-- jit.v or jit.profile, and jit.attach trace/record/compile/abort callbacks
-- never fire even when traces demonstrably compile (numeric loop: jit.off()
-- is 5.6x slower). Timing A/B is the only mechanism left on this engine.
--
-- Protocol rules (each one is a measurement that lied before being fixed):
--   * Fresh process per row. jit.off() does NOT evict already-compiled
--     traces, so same-session warm-then-off A/B silently reports 1.0x.
--   * jit.off() must run before any code under test compiles — it is the
--     first statement below and the mode is selected right after it.
--     (`nvim` does not accept `-j off`; the flag is luajit-CLI-only.)
--   * Vary loop inputs. The new engine hoists loop-invariant pure calls
--     (s:find(...) on a constant string measured ~1 ns/call this way).
--   * Startup never warms traces: `first=` below is the honest cold number;
--     `reload10=` approximates reload_all-style repeated compiles.
--
-- Usage (from the repo root, one fresh process per row, 3 rows per mode):
--   for m in on off; do for r in 1 2 3; do
--     JIT=$m N=100 nvim --clean -l tests/benchmarks/jit_ab.lua
--   done; done
--   for m in on off; do
--     WORKLOAD=probe JIT=$m nvim --clean -l tests/benchmarks/jit_ab.lua
--   done
--
-- Baselines and interpretation: docs/performance.md.

jit.off() -- first statement: the mode must be set before anything else compiles
local mode = vim.env.JIT or "on"
if mode ~= "off" then
	jit.on()
end

local workload = vim.env.WORKLOAD or "compile"

if workload == "compile" then
	vim.opt.rtp:prepend(vim.uv.cwd())
	local compile = require("laze.compile")
	local n = tonumber(vim.env.N or "40")

	local specs = {}
	for i = 1, n do
		specs[i] = {
			("owner-%d/plugin-telescope.nvim"):format(i),
			name = ("Telescope-%d"):format(i),
			event = "VeryLazy",
			keys = { { ("<leader>t%d"):format(i), "<cmd>Telescope<cr>" } },
			ft = { "lua", "vim" },
			cmd = { "Telescope" },
			build = "make",
		}
	end

	-- one-shot, like a real startup
	local t0 = vim.uv.hrtime()
	compile.compile(specs)
	local t1 = vim.uv.hrtime()
	-- reload pass, like reload_all()
	for _ = 1, 10 do
		compile.compile(specs)
	end
	local t2 = vim.uv.hrtime()

	print(
		("jit=%s n=%d first=%.2fms reload10=%.2fms status=%s"):format(
			mode,
			n,
			(t1 - t0) / 1e6,
			(t2 - t1) / 1e6,
			tostring(jit.status())
		)
	)
else
	-- SourcePre probe shapes: pattern find vs plain finds, over ROTATING
	-- inputs (a constant input gets hoisted — see header). This is the
	-- per-SourcePre-event cost of the plan.lua startup-phase probe.
	local INPUTS = {}
	for i = 1, 8 do
		INPUTS[i] = ("/home/u/.local/share/nvim/lazy/repo-%d/plugin/file-%d.lua"):format(i, i)
	end
	INPUTS[9] = "/home/u/.local/share/nvim/lazy/repo-x/lua/init.lua" -- miss
	INPUTS[10] = "/home/u/.local/share/nvim/lazy/repo-x/after/plugin/y.lua" -- miss

	local N = 2000000
	local t0 = vim.uv.hrtime()
	local hits = 0
	for i = 1, N do
		if INPUTS[(i % 10) + 1]:find("[/\\]plugin[/\\]") then
			hits = hits + 1
		end
	end
	local pattern = (vim.uv.hrtime() - t0) / N

	t0 = vim.uv.hrtime()
	hits = 0
	for i = 1, N do
		local s = INPUTS[(i % 10) + 1]
		if s:find("/plugin/", 1, true) or s:find("\\plugin\\", 1, true) then
			hits = hits + 1
		end
	end
	local plain = (vim.uv.hrtime() - t0) / N

	print(
		("jit=%s pattern=%.1fns plain=%.1fns ratio=%.2fx status=%s"):format(
			mode,
			pattern,
			plain,
			pattern / plain,
			tostring(jit.status())
		)
	)
end
