-- lazy.nvim's `version` is a semver range, not a git ref. vim.version.range
-- is lenient enough to misparse refs ("abc123" → 123.0.0), drop everything
-- after the first comparator ("1.2 || 1.3", ">=1.2.0 <2.0.0"), and ignore
-- trailing junk. Validate the whole string before handing it to vim.pack so
-- an unrepresentable range fails at compile time instead of silently
-- narrowing. Refs belong in branch/tag/commit.
local function is_digit(b)
	return b ~= nil and b >= 48 and b <= 57
end

local function is_wildcard(b)
	return b == 42 or b == 120 or b == 88 -- * x X
end

local function is_ident_byte(b)
	return b ~= nil
		and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 45)
end

-- Scan one version token after an optional comparator. Accepts the shapes
-- lazy.nvim/vim.version.range support: partial versions, x/X/* wildcards,
-- prerelease, and build metadata. Returns false on any trailing bytes.
local function is_version_token(s, i)
	local n = #s
	local b = s:byte(i)
	if b == 118 or b == 86 then -- v / V
		i = i + 1
	end
	if not is_digit(s:byte(i)) then
		return false
	end

	local numeric = 0
	local wildcard = false
	while i <= n do
		b = s:byte(i)
		if is_digit(b) then
			if wildcard then
				return false -- no numeric component after a wildcard
			end
			repeat
				i = i + 1
			until not is_digit(s:byte(i))
			numeric = numeric + 1
		elseif is_wildcard(b) then
			wildcard = true
			i = i + 1
		else
			break
		end
		if s:byte(i) == 46 then -- "."
			i = i + 1
			if i > n then
				return false
			end
		else
			break
		end
	end
	if numeric == 0 or numeric > 3 then
		return false
	end

	-- Prerelease/build after a wildcard would be stripped by vim.version.range
	-- along with the wildcard, so reject it rather than guess.
	if wildcard and (s:byte(i) == 45 or s:byte(i) == 43) then
		return false
	end

	local function scan_identifiers(j, stop_at_plus)
		local start = j
		while j <= n do
			local bb = s:byte(j)
			if is_ident_byte(bb) then
				j = j + 1
			elseif bb == 46 then -- "."
				if j == start or s:byte(j - 1) == 46 then
					return false
				end
				j = j + 1
				if not is_ident_byte(s:byte(j)) then
					return false
				end
			elseif bb == 43 and stop_at_plus then -- "+"
				break
			else
				return false
			end
		end
		if j == start then
			return false
		end
		return j
	end

	if s:byte(i) == 45 then -- "-" prerelease
		i = scan_identifiers(i + 1, true)
		if i == false then
			return false
		end
	end
	if s:byte(i) == 43 then -- "+" build
		i = scan_identifiers(i + 1, false)
		if i == false then
			return false
		end
	end
	return i > n
end

local function is_range_operand(s, allow_comparator)
	local i = 1
	if allow_comparator then
		local b = s:byte(i)
		if b == 62 or b == 60 then -- > <
			if s:byte(i + 1) == 61 then -- >= <=
				i = i + 2
			else
				i = i + 1
			end
		elseif b == 94 or b == 126 or b == 61 then -- ^ ~ =
			i = i + 1
		end
	end
	return is_version_token(s, i)
end

local function looks_like_semver_range(v)
	local n = #v
	if n == 0 then
		return true -- lazy.nvim and vim.version.range treat "" as "*"
	end
	if n == 1 and v:byte(1) == 42 then -- "*"
		return true
	end

	-- The only whitespace accepted is a single hyphen-range separator. This
	-- rejects compound ranges (" >=1.2.0 <2.0.0") instead of letting
	-- vim.version.range keep only the first comparator.
	local hyphen = v:find(" - ", 1, true)
	if hyphen then
		if v:find(" - ", hyphen + 3, true) then
			return false
		end
		local a = v:sub(1, hyphen - 1)
		local b = v:sub(hyphen + 3)
		return a ~= "" and b ~= "" and is_range_operand(a, false) and is_range_operand(b, false)
	end
	for i = 1, n do
		local b = v:byte(i)
		if b == 32 or b == 9 or b == 10 or b == 13 then
			return false
		end
	end
	return is_range_operand(v, true)
end

--- lazy.nvim's SemverRange:matches requires the candidate's prerelease to
--- equal the lower bound's prerelease (`version.prerelease ~=
--- self.from.prerelease` -> false). `vim.version.range` does not apply that
--- filter, so a `>1.2.3` range would otherwise include `1.2.4-alpha`.
--- Extract the lower bound's prerelease from the input spec (comparator and
--- hyphen form) and wrap only `has`: the range check itself stays Neovim's.
---@param spec string
---@param range vim.VersionRange
---@return vim.VersionRange
local function with_lower_prerelease(spec, range)
	local lower = spec
	local hyphen = spec:find(" - ", 1, true)
	if hyphen then
		lower = spec:sub(1, hyphen - 1)
	end
	local version = lower:lower():match("^[%^=<>~]*(.*)$") or ""
	version = version:gsub("%.[%*x]", "")
	local ok, parsed = pcall(vim.version.parse, version)
	local want = ok and parsed and parsed.prerelease or nil

	local wrapper = { from = range.from, to = range.to }
	wrapper.has = function(_, candidate)
		local version_obj = candidate
		if type(candidate) == "string" then
			local parsed_ok, parsed_obj = pcall(vim.version.parse, (candidate:gsub("^v", "")))
			if not parsed_ok or not parsed_obj then
				return false
			end
			version_obj = parsed_obj
		end
		if (version_obj.prerelease or nil) ~= want then
			return false
		end
		return range:has(version_obj)
	end
	return setmetatable(wrapper, {
		__index = range,
		__tostring = function()
			return tostring(range)
		end,
	})
end

---@param v string
---@param idx? integer
---@param spec_id? string
---@return vim.VersionRange
local function to_semver_range(v, idx, spec_id)
	local prefix = idx and ("spec [" .. idx .. "]" .. (spec_id and (" (" .. spec_id .. ")") or "") .. ": ") or ""
	if not looks_like_semver_range(v) then
		error(
			prefix
				.. ("version %q is not a supported semver range (single ranges only; multi-range/whitespace sets are rejected; git refs belong in branch/tag/commit)"):format(
					v
				),
			0
		)
	end
	local range_fn = vim.version and vim.version.range
	if type(range_fn) ~= "function" then
		error(prefix .. "vim.version.range is required to lower version ranges", 0)
	end
	local ok, range = pcall(range_fn, v)
	if not ok or range == nil then
		error(prefix .. ("version %q is not a valid semver range"):format(v), 0)
	end
	-- Non-Neovim test stub: keep the value opaque.
	if type(range) ~= "table" or type(range.has) ~= "function" then
		return range
	end
	return with_lower_prerelease(v, range)
end

return {
	to_semver_range = to_semver_range,
};
