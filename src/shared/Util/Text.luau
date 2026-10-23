--!strict
-- Player-facing text by localization key (client side). Russian for ru-* Roblox locales, English otherwise.

local LocalizationService = game:GetService("LocalizationService")

local Strings = require("../Config/Strings")

local russian = string.sub(LocalizationService.RobloxLocaleId, 1, 2) == "ru"
local overrides: { [string]: { en: string, ru: string } } = {} -- from live config (title renames)

local Text = {}

function Text.override(key: string, entry: { en: string, ru: string }?)
	overrides[key] = entry :: any
end

function Text.get(key: string): string
	local entry = overrides[key] or Strings[key]
	if not entry then
		warn(`[Text] missing key {key}`)
		return key
	end
	return if russian then entry.ru else entry.en
end

-- Text with {name} placeholders filled from `values`.
function Text.format(key: string, values: { [string]: string | number }): string
	return (
		string.gsub(Text.get(key), "{(%w+)}", function(name)
			local value = values[name]
			return if value ~= nil then tostring(value) else "{" .. name .. "}"
		end)
	)
end

return Text
