--- Snapshot updater for laze compile tests
---
--- Regenerates all snapshot files from current compile output.
--- Run: nvim --cmd "set rtp+=." -l tests/update_snapshots.lua
--- Or (standalone): luajit tests/update_snapshots.lua (if run from repo root)
package.path = string.format("./lua/?.lua;%s", package.path)

local compile = require("laze.compile").compile
local FN = require("tests.fixtures._sentinel").FN

-- Stub vim for plain Lua
if not vim then
	vim = {}
	vim.log = { levels = { WARN = "WARN" } }
	vim.notify = function() end
	vim.fn = {
		expand = function(s)
			return s:gsub("^~", os.getenv("HOME") or "")
		end,
	}
	vim.inspect = function(v)
		if type(v) == "string" then
			return string.format("%q", v)
		end
		if type(v) == "nil" then
			return "nil"
		end
		if type(v) == "table" then
			local parts = {}
			for k, val in pairs(v) do
				table.insert(parts, string.format("%s = %s", vim.inspect(k), vim.inspect(val)))
			end
			return "{" .. table.concat(parts, ", ") .. "}"
		end
		return tostring(v)
	end
end

local FIXTURE_DIR = "tests/fixtures"
local SNAPSHOT_DIR = "tests/snapshots"

local fixtures = {
	"basic",
	"dev_key",
	"disabled",
	"after_deps",
	"name_override",
	"dir_source",
	"dependencies",
	"silent",
	"cond",
	"version_data",
	"unknown_fields",
	"module_trigger",
	"build_dev",
	"keys_rhs",
	"deps_dedup",
	"event_pattern",
	"keys_opts",
	"cond_enabled",
	"name_derivation",
	"priority_build",
	"opts_main",
}

local function serialize(val, indent)
	indent = indent or 0
	local pad = string.rep("\t", indent)

	if val == nil then
		return "nil"
	end
	if val == true then
		return "true"
	end
	if val == false then
		return "false"
	end
	if type(val) == "number" then
		return tostring(val)
	end
	if type(val) == "string" then
		return ("%q"):format(val)
	end
	if type(val) == "function" then
		return "FN"
	end
	if type(val) == "table" then
		local is_array = true
		for k in pairs(val) do
			if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
				is_array = false
				break
			end
		end
		if is_array then
			local parts = {}
			for i, v in ipairs(val) do
				parts[i] = pad .. "\t" .. serialize(v, indent + 1)
			end
			if #parts == 0 then
				return "{}"
			end
			return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. pad .. "}"
		else
			local keys = {}
			for k in pairs(val) do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				if type(a) ~= type(b) then
					return type(a) < type(b)
				end
				return tostring(a) < tostring(b)
			end)
			local parts = {}
			for _, k in ipairs(keys) do
				local ks = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or ("[" .. serialize(k) .. "]")
				table.insert(parts, pad .. "\t" .. ks .. " = " .. serialize(val[k], indent + 1))
			end
			if #parts == 0 then
				return "{}"
			end
			return "{\n" .. table.concat(parts, ",\n") .. ",\n" .. pad .. "}"
		end
	end
	error("cannot serialize type " .. type(val))
end

local function serialize_compiled(compiled)
	local lines = {}
	table.insert(lines, 'local FN = require("tests.fixtures._sentinel").FN')
	table.insert(lines, "")
	table.insert(lines, "return " .. serialize(compiled, 0))
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

os.execute("mkdir -p " .. SNAPSHOT_DIR)

for _, name in ipairs(fixtures) do
	local ok, fixture = pcall(require, "tests.fixtures." .. name)
	if not ok then
		print(("  ✗ %s: could not load fixture — %s"):format(name, fixture))
	else
		local compiled = compile(fixture.specs, fixture.opts)
		local content = serialize_compiled(compiled)
		local path = SNAPSHOT_DIR .. "/" .. name .. ".lua"
		local f = io.open(path, "w")
		if f then
			f:write(content)
			f:close()
			print(("  ✓ %s: snapshot written"):format(name))
		else
			print(("  ✗ %s: could not write %s"):format(name, path))
		end
	end
end

print("\nSnapshots updated in " .. SNAPSHOT_DIR .. "/")
