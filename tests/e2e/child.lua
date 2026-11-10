--- One isolated headless Neovim per plugin: compile+setup (install), fire the
--- matrix trigger, run one smoke assertion, write a JSON result.
local name = assert(vim.env.LAZE_E2E_NAME, "LAZE_E2E_NAME")
local spec_path = assert(vim.env.LAZE_E2E_SPEC, "LAZE_E2E_SPEC")
local out = assert(vim.env.LAZE_E2E_OUT, "LAZE_E2E_OUT")
local trigger = vim.json.decode(vim.env.LAZE_E2E_TRIGGER or '{"kind":"none"}')
local smoke = vim.json.decode(vim.env.LAZE_E2E_SMOKE or '{"kind":"none"}')

local started = vim.uv.hrtime()
local warnings = {}
local result = { name = name, status = "failed", category = "runtime_error", warnings = warnings }

local function finish()
	result.duration_ms = math.floor((vim.uv.hrtime() - started) / 1e6)
	pcall(vim.fn.writefile, { vim.json.encode(result) }, out)
	vim.cmd("qall!")
end

local function fail(category, err)
	result.category = category
	result.error = tostring(err)
	finish()
end

local function has(message, needle)
	return message:find(needle, 1, true) ~= nil
end

local function classify(err)
	local message = tostring(err):lower()
	if
		has(message, "vim.pack")
		or has(message, "could not resolve host")
		or has(message, "unable to access")
		or has(message, "connection refused")
		or has(message, "timed out")
		or has(message, "failed to clone")
		or has(message, "clone failed")
	then
		return "install_error"
	end
	if
		has(message, "executable")
		or has(message, "command not found")
		or has(message, "no such file or directory")
		or has(message, "permission denied")
	then
		return "environment"
	end
	return "runtime_error"
end

local function is_unsupported_warning(message)
	local m = message:lower()
	return has(m, "not supported") or has(m, "no equivalent") or has(m, "lazy.nvim-only") or has(m, "unsupported")
end

-- Capture compile warnings without printing install progress.
local original_notify = vim.notify
vim.notify = function(message, level)
	if level == vim.log.levels.WARN or level == vim.log.levels.ERROR then
		table.insert(warnings, tostring(message))
	end
end

local chunk, load_err = loadfile(spec_path)
if not chunk then
	fail("extraction_error", load_err)
end
local spec_ok, specs = pcall(chunk)
if not spec_ok or type(specs) ~= "table" then
	fail("extraction_error", specs)
end

local laze = require("laze")
local compile_ok, compile_err = pcall(laze.compile, specs)
if not compile_ok then
	fail("validation_error", compile_err)
end

local setup_ok, setup_err = pcall(laze.setup, specs)
vim.notify = original_notify
if not setup_ok then
	fail(classify(setup_err), setup_err)
end

local function fire(t)
	if t.kind == "none" then
		return
	end
	if t.kind == "event" then
		if t.value == "VeryLazy" then
			vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
		else
			vim.api.nvim_exec_autocmds(t.value, {})
		end
	elseif t.kind == "ft" then
		vim.bo.filetype = t.value
	elseif t.kind == "cmd" then
		vim.cmd(t.value)
	elseif t.kind == "keys" then
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(t.value, true, false, true), "x", false)
	elseif t.kind == "module" then
		require(t.value)
	else
		error("unknown trigger kind: " .. tostring(t.kind))
	end
end

local fire_ok, fire_err = pcall(fire, trigger)
if not fire_ok then
	fail(classify(fire_err), fire_err)
end

if smoke.kind == "module" then
	local smoke_ok, smoke_err = pcall(require, smoke.value)
	if not smoke_ok then
		fail(classify(smoke_err), smoke_err)
	end
elseif smoke.kind == "cmd" then
	if vim.fn.exists(":" .. smoke.value) == 0 then
		fail("runtime_error", "command not found: " .. tostring(smoke.value))
	end
elseif smoke.kind ~= "none" then
	fail("runtime_error", "unknown smoke kind: " .. tostring(smoke.kind))
end

for _, warning in ipairs(warnings) do
	if is_unsupported_warning(warning) then
		result.status = "warned"
		result.category = "unsupported_field"
		break
	end
end
if result.status ~= "warned" then
	result.status = "ok"
	result.category = nil
end
finish()
