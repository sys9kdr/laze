-- Parse cost oracle: median in-process load() time per file. Parsing scales
-- with bytes (~5.2-6.3 ns/B measured), so "move startup-parsed code behind a
-- lazy require" work is gated here: the load() median is stable in-process,
-- while fresh-process deltas (req.plan in breakdown.lua) sit under a
-- +-100 us inter-process noise floor.
-- Run from the repo root:
--   nvim --clean -l tests/benchmarks/parse_cost.lua lua/laze/plan.lua,lua/laze/compile.lua
-- The file list is the LAST argv entry joined by commas (`nvim -l` does not
-- pass script varargs); without it the core startup trio is measured.
local function readfile(p)
	local f = assert(io.open(p, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local function median(t)
	table.sort(t)
	return t[math.floor(#t / 2) + 1]
end

local function cost(path)
	local src = readfile(path)
	local times = {}
	for i = 1, 60 do
		local t0 = vim.uv.hrtime()
		assert(load(src, path))
		times[i] = (vim.uv.hrtime() - t0) / 1000
	end
	return median(times), #src
end

local arg = vim.v.argv[#vim.v.argv]
local files = arg:find(",", 1, true) and arg or "lua/laze/compile.lua,lua/laze/plan.lua,lua/laze/init.lua"
for line in files:gmatch("[^,]+") do
	local us, n = cost(line)
	print(("%-28s %6.1fus  %6dB  %.1fns/B"):format(line, us, n, us * 1000 / n))
end
