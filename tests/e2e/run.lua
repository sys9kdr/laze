--- README e2e driver. Manual/network only: fetches each plugin's README at the
--- pinned SHA, extracts the first lazy.nvim spec table verbatim (wrapping a
--- bare `{ ... }` with `return`), then spawns one isolated headless Neovim per
--- plugin to install, fire the matrix trigger, and run one smoke assertion.
---
--- Run: nvim --cmd "set rtp+=." -l tests/run.lua e2e_readme [--clean] [--failed] [name ...]
--- Output: one row per plugin plus tests/e2e/report/<timestamp>.json.
--- Environment failures (network, missing external binaries) are their own
--- category and do not count as laze regressions.
local root = vim.fn.getcwd()
local cache_root = "/tmp/laze-e2e"
local report_dir = root .. "/tests/e2e/report"
local matrix = dofile(root .. "/tests/e2e/matrix.lua")

local wanted = {}
local clean = false
local failed_only = false
for i = 1, #arg do
	local value = arg[i]
	if value == "e2e_readme" then
		-- entry marker from tests/run.lua
	elseif value == "--clean" then
		clean = true
	elseif value == "--failed" then
		failed_only = true
	else
		wanted[value] = true
	end
end

if clean then
	vim.fn.delete(cache_root, "rf")
end
vim.fn.mkdir(report_dir, "p")

local function fetch(url)
	local obj = vim.system({ "curl", "-fsSL", url }, { text = true }):wait()
	if obj.code ~= 0 then
		return nil, (obj.stderr or ""):gsub("%s+$", "")
	end
	return obj.stdout
end

local function strip_leading_comments(src)
	src = src:gsub("^\r?\n", "")
	while true do
		local line, rest = src:match("^([^\n]*)\n(.*)$")
		if not line then
			break
		end
		if line:match("^%s*$") or line:match("^%s*%-%-") then
			src = rest
		else
			break
		end
	end
	return src:gsub("^%s+", "")
end

local function looks_like_spec(value)
	if type(value) ~= "table" then
		return false
	end
	local first = value[1]
	if type(first) == "string" then
		return first:find("/", 1, true) ~= nil
	end
	if type(first) == "table" then
		local name = first[1]
		return type(name) == "string" and name:find("/", 1, true) ~= nil
	end
	return false
end

local function extract_spec(readme)
	for block in readme:gmatch("```lua[^\n]*\n(.-)```") do
		local src = strip_leading_comments(block)
		local chunk_src
		if src:sub(1, 1) == "{" then
			chunk_src = "return " .. src
		elseif src:match("^return%s*{") then
			chunk_src = src
		end
		if chunk_src then
			local chunk = load(chunk_src, "readme-spec")
			if chunk then
				local ok, value = pcall(chunk)
				if ok and looks_like_spec(value) then
					return chunk_src
				end
			end
		end
	end
	return nil
end

local function latest_report()
	local files = vim.fn.glob(report_dir .. "/*.json", false, true)
	table.sort(files)
	return files[#files]
end

local function failed_names()
	local path = latest_report()
	if not path then
		return {}
	end
	local ok, data = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
	end)
	local names = {}
	if ok and type(data) == "table" and type(data.results) == "table" then
		for _, result in ipairs(data.results) do
			if result.status ~= "ok" then
				names[result.name] = true
			end
		end
	end
	return names
end

if failed_only then
	wanted = failed_names()
	if not next(wanted) then
		print("e2e_readme: no previously failed plugins")
		os.exit(0)
	end
end

local function make_job(entry)
	local suffix = entry.sha:sub(1, 8)
	local dir = cache_root .. "/" .. entry.name .. "-" .. suffix
	local xdg = {
		config = dir .. "/config",
		data = dir .. "/data",
		state = dir .. "/state",
		cache = dir .. "/cache",
	}
	for _, path in pairs(xdg) do
		vim.fn.mkdir(path, "p")
	end

	local url = ("https://raw.githubusercontent.com/%s/%s/README.md"):format(entry.repo, entry.sha)
	local readme, fetch_err = fetch(url)
	local spec_path = dir .. "/spec.lua"
	local result_path = dir .. "/result.json"
	vim.fn.delete(result_path)

	if not readme then
		return {
			entry = entry,
			dir = dir,
			result_path = result_path,
			fetch_error = fetch_err,
		}
	end
	local spec = extract_spec(readme)
	if not spec then
		return {
			entry = entry,
			dir = dir,
			result_path = result_path,
			extract_error = "no lazy.nvim spec table found in README",
		}
	end
	vim.fn.writefile(vim.split(spec, "\n", { plain = true }), spec_path)
	return {
		entry = entry,
		dir = dir,
		spec_path = spec_path,
		result_path = result_path,
		xdg = xdg,
	}
end

local jobs = {}
for _, entry in ipairs(matrix) do
	if not next(wanted) or wanted[entry.name] then
		jobs[#jobs + 1] = make_job(entry)
	end
end
if #jobs == 0 then
	print("e2e_readme: no matching plugins")
	os.exit(0)
end

local function read_result(job, obj)
	if job.fetch_error then
		return {
			name = job.entry.name,
			status = "failed",
			category = "environment",
			error = "README fetch failed: " .. job.fetch_error,
		}
	end
	if job.extract_error then
		return { name = job.entry.name, status = "failed", category = "extraction_error", error = job.extract_error }
	end
	if vim.fn.filereadable(job.result_path) == 1 then
		local ok, result = pcall(function()
			return vim.json.decode(table.concat(vim.fn.readfile(job.result_path), "\n"))
		end)
		if ok then
			result.name = job.entry.name
			return result
		end
	end
	local stderr = obj and obj.stderr or ""
	local category = (obj and obj.code == 124) and "environment" or "runtime_error"
	return {
		name = job.entry.name,
		status = "failed",
		category = category,
		error = "child produced no result: " .. (stderr:gsub("%s+$", "")),
	}
end

local function spawn(job, on_exit)
	local env = {
		XDG_CONFIG_HOME = job.xdg.config,
		XDG_DATA_HOME = job.xdg.data,
		XDG_STATE_HOME = job.xdg.state,
		XDG_CACHE_HOME = job.xdg.cache,
		LAZE_E2E_NAME = job.entry.name,
		LAZE_E2E_SPEC = job.spec_path,
		LAZE_E2E_OUT = job.result_path,
		LAZE_E2E_TRIGGER = vim.json.encode(job.entry.trigger),
		LAZE_E2E_SMOKE = vim.json.encode(job.entry.smoke),
	}
	local cmd = { "nvim", "--cmd", "set rtp+=" .. root, "--headless", "-l", "tests/e2e/child.lua" }
	return vim.system(cmd, { cwd = root, env = env, timeout = 240000 }, on_exit)
end

local results = {}
local index = 0
local active = 0
local done = false

local function finish_one(job, obj)
	local result = read_result(job, obj)
	results[job.entry.name] = result
	active = active - 1
end

local function start_next()
	while active < 4 and index < #jobs do
		index = index + 1
		local job = jobs[index]
		if job.fetch_error or job.extract_error then
			finish_one(job)
		else
			active = active + 1
			local ok, handle = pcall(spawn, job, function(obj)
				vim.schedule(function()
					finish_one(job, obj)
					start_next()
				end)
			end)
			if not ok then
				results[job.entry.name] = {
					name = job.entry.name,
					status = "failed",
					category = "environment",
					error = tostring(handle),
				}
				active = active - 1
			end
		end
	end
	if index >= #jobs and active == 0 then
		done = true
	end
end

vim.fn.mkdir(cache_root, "p")
start_next()
vim.wait(3600000, function()
	return done
end, 200)

local ordered = {}
for _, job in ipairs(jobs) do
	local name = job.entry.name
	-- Re-read the file after every child has exited: the callback's read can
	-- race a not-yet-visible result on a busy parallel run.
	local result = read_result(job, nil)
	if result.error and result.error:find("child produced no result", 1, true) then
		result = results[name] or result
	end
	ordered[#ordered + 1] = result
	print(
		("%-12s %-7s %-16s %6s  %s"):format(
			result.name,
			result.status,
			result.category or "-",
			result.duration_ms and (result.duration_ms .. "ms") or "-",
			result.error or ""
		)
	)
	if result.warnings and #result.warnings > 0 then
		print(("  warnings: %d"):format(#result.warnings))
	end
end

local stamp = os.date("%Y%m%dT%H%M%S")
local report_path = report_dir .. "/" .. stamp .. ".json"
local report = { date = stamp, results = ordered }
vim.fn.writefile({ vim.json.encode(report) }, report_path)
print("report: " .. report_path)

local regressions = 0
for _, result in ipairs(ordered) do
	if result.status ~= "ok" and result.category ~= "environment" then
		regressions = regressions + 1
	end
end
if regressions > 0 then
	os.exit(1)
end
