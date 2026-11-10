--- Benchmark: plan registration only (no plugin loading)
--- Run: nvim --cmd "set rtp+=." -l tests/benchmarks/bench.lua
local laze = require("laze")
local uv = vim.uv or vim.loop

local function elapsed_us(start)
	return (uv.hrtime() - start) / 1000
end

laze.compile({ { "u/warmup", event = "VeryLazy" } })

print("=== laze benchmark (registration only) ===\n")

local N = 100
local specs = {}
for i = 1, N do
	local s = { ("user/plugin-%d"):format(i), name = ("p%d"):format(i) }
	if i % 3 == 0 then
		s.event = "VeryLazy"
	end
	if i % 5 == 0 then
		s.ft = { "lua", "vim" }
	end
	if i % 7 == 0 then
		s.cmd = ("Cmd%d"):format(i)
	end
	if i % 11 == 0 then
		s.keys = { ("<leader>%d"):format(i) }
	end
	if i % 13 == 0 then
		s.after = { ("p%d"):format(i - 1) }
	end
	if i % 17 == 0 then
		s.dev = true
	end
	table.insert(specs, s)
end

local t0 = uv.hrtime()
local compiled = laze.compile(specs)
print(("compile %d specs: %.0f μs"):format(N, elapsed_us(t0)))

-- Before build_plan: the plan resolves `enabled` at build time, so a later
-- disable would leave plan() eagerly activating these.
for _, entry in pairs(compiled.registry) do
	entry.enabled = false
end

local t1 = uv.hrtime()
local plan = laze.build_plan(compiled)
print(("build_plan:     %.0f μs"):format(elapsed_us(t1)))

local t2 = uv.hrtime()
plan()
print(("plan() (no load): %.0f μs"):format(elapsed_us(t2)))

print("\n=== scale: compile ===\n")
for _, scale in ipairs({ 10, 50, 100, 200, 500 }) do
	local big = {}
	for i = 1, scale do
		table.insert(big, { ("u/p-%d"):format(i), cmd = ("C%d"):format(i) })
	end
	local t_scale = uv.hrtime()
	laze.compile(big)
	print(
		("compile %3d specs: %6.0f μs  (%5.2f μs/spec)"):format(scale, elapsed_us(t_scale), elapsed_us(t_scale) / scale)
	)
end

print("\n=== scale: plan (triggers only) ===\n")
local events_pool = { "BufRead", "BufWrite", "InsertEnter", "InsertLeave", "VimEnter" }
local fts_pool = { "lua", "vim", "python", "rust", "json" }

for _, scale in ipairs({ 10, 50, 100, 200 }) do
	local big = {}
	for i = 1, scale do
		table.insert(big, {
			("u/p-%d"):format(i),
			event = events_pool[(i % #events_pool) + 1],
			ft = fts_pool[(i % #fts_pool) + 1],
			cmd = "Cmd" .. i,
			keys = ("<leader>k%d"):format(i),
		})
	end
	local c = laze.compile(big)
	for _, entry in pairs(c.registry) do
		entry.enabled = false
	end
	local p = laze.build_plan(c)
	local t_plan = uv.hrtime()
	p()
	print(
		("plan %3d triggers (×4 types): %6.0f μs  (%5.2f μs/trigger)"):format(
			scale,
			elapsed_us(t_plan),
			elapsed_us(t_plan) / (scale * 4)
		)
	)
end

print("\n=== name derivation ===\n")

-- Name parity with vim.pack is asserted by the integration suite, not here.
local compile_mod = require("laze.compile")
local srcs = {}
for i = 1, 10000 do
	srcs[i] = ("https://github.com/user/plugin-%d.git"):format(i)
end

for i = 1, 100 do
	compile_mod.pkg_name(srcs[i])
	compile_mod.derive_name(srcs[i])
end

local best, acc = math.huge, 0
for _ = 1, 3 do
	local t_names = uv.hrtime()
	acc = 0
	for i = 1, #srcs do
		acc = acc + #compile_mod.pkg_name(srcs[i]) + #compile_mod.derive_name(srcs[i])
	end
	best = math.min(best, elapsed_us(t_names))
end
print(("derive_name+pkg_name x%d: %6.0f μs best-of-3 (%.3f μs/pair, acc=%d)"):format(#srcs, best, best / #srcs, acc))
