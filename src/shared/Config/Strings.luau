--!strict
-- Player-facing text by key (en + ru). Source for the LocalizationTable; no hardcoded UI strings.

return {
	PROMPT_PLAY = { en = "Play", ru = "Играть" },
	PROMPT_TABLE = { en = "Pool table", ru = "Бильярдный стол" },
	HUD_LEAVE = { en = "Stand up", ru = "Встать" },
	HUD_RERACK = { en = "Re-rack", ru = "Расставить заново" },
	HUD_SPIN = { en = "Spin", ru = "Винт" },
	HUD_POWER = { en = "Power", ru = "Сила" },
	HUD_FINE = { en = "Fine", ru = "Точно" },
	HUD_ELEVATION = { en = "Cue elevation", ru = "Подъём кия" },
	HUD_SPIN_RESET = { en = "Center", ru = "Центр" },
	HUD_CLOSE = { en = "Done", ru = "Готово" },
} :: { [string]: { en: string, ru: string } }
