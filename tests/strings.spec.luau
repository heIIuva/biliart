--!strict
-- Every localization key written literally in src exists in Strings (en and ru). Keys built at
-- runtime ("EVENT_" .. id) are not seen here; the Config tests cover those tables.
local fs = require("@lune/fs")
local Strings = require("../src/shared/Config/Strings")

local PATTERNS = {
	'Text%.get%("([A-Z][A-Z0-9_]+)"',
	'Text%.format%("([A-Z][A-Z0-9_]+)"',
	'notify%([%w_]+, "([A-Z][A-Z0-9_]+)"',
	'%a*Key = "([A-Z][A-Z0-9_]+)"',
	'Kit%.button%([^,]+, [%w_]+, "([A-Z][A-Z0-9_]+)"',
}

local function walk(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			if name ~= "Packages" then
				walk(path, out)
			end
		elseif name:match("%.luau$") then
			table.insert(out, path)
		end
	end
end

return {
	["every literal key used in code exists in Strings"] = function()
		local files = {}
		walk("src", files)
		local missing = {}
		for _, path in files do
			local source = fs.readFile(path)
			for _, pattern in PATTERNS do
				for key in source:gmatch(pattern) do
					if key:sub(-1) ~= "_" and not Strings[key] then -- "EVENT_" .. id: a prefix
						table.insert(missing, `{key} ({path})`)
					end
				end
			end
		end
		assert(#missing == 0, "missing keys: " .. table.concat(missing, ", "))
	end,
	["keys built from ids exist"] = function()
		local keys = { "SETTINGS_MUSIC", "SETTINGS_SFX", "SETTINGS_ANNOUNCER", "QUALITY_AUTO", "QUALITY_LOW" }
		for _, id in { "GoldenHour", "TigerNight", "LanternRain" } do
			table.insert(keys, "EVENT_" .. string.upper(id))
		end
		for _, id in { "AllTiger", "GoldenRain", "TripleRewards" } do
			table.insert(keys, "ADMIN_" .. string.upper(id))
		end
		for _, key in keys do
			assert(Strings[key], `missing {key}`)
		end
	end,
	["every entry has en and ru"] = function()
		for key, entry in Strings do
			assert(entry.en ~= "" and entry.ru ~= "", `empty text for {key}`)
		end
	end,
}
