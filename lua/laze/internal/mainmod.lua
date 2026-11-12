-- Main-module resolution for the desugared `config = true` closure. Separate file so its parse cost is paid only when a
-- plugin actually loads. lazy.nvim's Util.normname, kept equivalent so both pick the same module.
local function norm_module_name(name)
	return name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("[^a-z]+", "")
end

--- Resolve a plugin's `main` module like lazy.nvim when `opts` or `config = true` has no explicit main.
--- Runs at load time, when the plugin is installed.
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
}
