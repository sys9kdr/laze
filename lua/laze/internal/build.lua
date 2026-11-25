--- PackChanged build runner, required only when an install/update fires. Shell items run through vim.system callbacks
--- so the editor stays responsive; items of one plugin run in order, plugins run in parallel.
local M = {}

-- Fresh installs at startup must finish before the plan loads plugins (lazy.nvim 306a055 waits on its startup
-- install, build included); vim.wait keeps the event loop and progress messages alive meanwhile.
local STARTUP_TIMEOUT_MS = 10 * 60 * 1000

local running = 0

---@param id integer?
---@param name string
---@param status "running"|"success"|"failed"
---@return integer?
local function progress(id, name, status)
	local text = status == "running" and "build " .. name or ("build %s: %s"):format(name, status)
	local ok, new_id = pcall(vim.api.nvim_echo, { { text } }, status ~= "running", {
		kind = "progress",
		source = "laze",
		title = "laze",
		status = status,
		id = id,
	})
	return ok and new_id or id
end

--- Whether the build needs the plugin activated before it runs: only `:` items do (their commands are
--- defined by plugin/, and lazy.nvim's build task loads the plugin for them). Shell and function items run
--- without activation.
---@param build string|fun(plugin: table)|(string|fun(plugin: table))[]
---@return boolean
function M.needs_activation(build)
	if type(build) == "string" then
		return build:sub(1, 1) == ":"
	end
	if type(build) == "function" then
		return false
	end
	for _, item in ipairs(build) do
		if type(item) == "string" and item:sub(1, 1) == ":" then
			return true
		end
	end
	return false
end

--- Fallback for `:` items when `:packadd` could not resolve the pkg dir (a glob-magic pkg name is silently
--- skipped there): source plugin/ by exact path so the command is defined anyway. after/plugin stays with the
--- plan's finalizer, mirroring the same fallback in load_plugin.
---@param dir string
function M.source_plugin_files(dir)
	local escaped = (dir:gsub("[\\%[%]{}*?]", "\\%0"))
	for _, file in ipairs(vim.fn.glob(escaped .. "/plugin/**/*.{lua,vim}", false, true)) do
		pcall(vim.cmd.source, file)
	end
end

---@param build string|fun(plugin: table)|(string|fun(plugin: table))[]
---@param plugin { name: string, dir: string, spec: table }
function M.run(build, plugin)
	local items = type(build) == "table" and build or { build }
	running = running + 1
	local msg_id = progress(nil, plugin.name, "running")

	---@param err? string
	local function finish(err)
		running = running - 1
		progress(msg_id, plugin.name, err and "failed" or "success")
		if err then
			require("laze.internal.diag").warn(("build failed for %s: %s"):format(plugin.name, err))
		end
	end

	local function step(i)
		local item = items[i]
		if item == nil then
			return finish()
		end
		if type(item) == "function" then
			local ok, err = pcall(item, plugin)
			if not ok then
				return finish(tostring(err))
			end
			return step(i + 1)
		elseif item:sub(1, 1) == ":" then
			-- LuaLS sees `vim.cmd` as a callable table, not a function.
			---@diagnostic disable-next-line: param-type-mismatch
			local ok, err = pcall(vim.cmd, item)
			if not ok then
				return finish(tostring(err))
			end
			return step(i + 1)
		end
		local ok, err = pcall(
			vim.system,
			{ "sh", "-c", item },
			{ cwd = plugin.dir, text = true },
			vim.schedule_wrap(function(result)
				if result.code ~= 0 then
					return finish(("exit %d: %s"):format(result.code, result.stderr or ""))
				end
				step(i + 1)
			end)
		)
		if not ok then
			finish(tostring(err))
		end
	end

	step(1)
end

--- Block until in-flight builds finish; <C-c> or the timeout leaves them running in the background.
function M.wait()
	if running > 0 then
		vim.wait(STARTUP_TIMEOUT_MS, function()
			return running == 0
		end)
	end
end

return M
