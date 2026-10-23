--!strict
-- Player-facing text by localization key (client side). Russian for ru-* Roblox locales, English otherwise.

local LocalizationService = game:GetService("LocalizationService")

local Strings = require("../Config/Strings")

local russian = string.sub(LocalizationService.RobloxLocaleId, 1, 2) == "ru"

local Text = {}

function Text.get(key: string): string
	local entry = Strings[key]
	if not entry then
		warn(`[Text] missing key {key}`)
		return key
	end
	return if russian then entry.ru else entry.en
end

return Text
