-- Main-module resolution for the desugared `config = true` closure. Lives
-- apart from compile.lua so its parse cost is only paid when a plugin
-- actually loads (startup only parses compile.lua via the require graph).
-- lazy.nvim's Util.normname: used to match a plugin name against the
-- top-level Lua modules it ships. Kept equivalent to lazy/core/util.lua so
-- main-module resolution picks the same module.
local function norm_module_name(name)
	return name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("[^a-z]+", "")
end

--- Resolve a plugin's `main` module the way lazy.nvim does when `opts` or
--- `config = true` is used without an explicit `main`:
---   * `mini.<name>` plugins use their own name (except `mini.nvim`),
---   * otherwise scan the top-level entries under `<plugin>/lua`, prefer a
---     module whose normalized name matches the plugin name, and fall back
---     to the single module when the plugin ships exactly one.
--- Runs at load time (the plugin is installed by then), never at compile.
---@param plugin_dir string?
---@param name string
---@return string?
local function get_main(plugin_dir, name)
	if name ~= "mini.nvim" and name:match("^mini%.") then
		return name
	end
	if not plugin_dir then
		return nil
	end
	local uv = vim.uv or vim.loop
	local lua_dir = plugin_dir .. "/lua"
	local handle = uv.fs_scandir(lua_dir)
	if not handle then
		return nil
	end
	local normname = norm_module_name(name)
	local mods = {}
	local seen = {}
	while true do
		local entry_name, t = uv.fs_scandir_next(handle)
		if not entry_name then
			break
		end
		local topname
		local ext = entry_name:sub(-4)
		if ext == ".lua" or ext == ".dll" then
			topname = entry_name:sub(1, -5)
		elseif entry_name:sub(-3) == ".so" then
			topname = entry_name:sub(1, -4)
		elseif t == "link" or t == "directory" then
			topname = entry_name
		elseif t == nil then
			-- luv occasionally omits the type; stat it like lazy.nvim does.
			local st = uv.fs_stat(lua_dir .. "/" .. entry_name)
			if st and (st.type == "link" or st.type == "directory") then
				topname = entry_name
			end
		end
		if topname and not seen[topname] then
			seen[topname] = true
			if norm_module_name(topname) == normname then
				return topname
			end
			table.insert(mods, topname)
		end
	end
	return #mods == 1 and mods[1] or nil
end

return {
	get_main = get_main,
};
