--!strict
-- Quick chat (GDD 15): ready-made phrases and emotes only, no free text (so no filtering needed).
-- emote: default Roblox emote name until own animations exist; sound: Config.Assets key.

export type Entry = { id: string, key: string, emote: string?, sound: string? }

return {
	Phrases = {
		{ id = "HuHu", key = "CHAT_HUHU" },
		{ id = "GoodLuck", key = "CHAT_GOOD_LUCK" },
		{ id = "OnPurpose", key = "CHAT_ON_PURPOSE" },
		{ id = "Again", key = "CHAT_AGAIN" },
		{ id = "NiceShot", key = "CHAT_NICE_SHOT" },
		{ id = "Oops", key = "CHAT_OOPS" },
	} :: { Entry },
	Emotes = {
		{ id = "Roar", key = "EMOTE_ROAR", emote = "point", sound = "TigerRoar" },
		{ id = "Gong", key = "EMOTE_GONG", emote = "wave", sound = "Gong" },
		{ id = "Bow", key = "EMOTE_BOW", emote = "wave" },
		{ id = "Dance", key = "EMOTE_DANCE", emote = "dance1" },
	} :: { Entry },
	ShowSeconds = 3,
}
