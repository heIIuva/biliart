--!strict
-- Event schedule (GDD 16), computed from os.time() in UTC — identical on every server, no
-- coordination needed. Live config can override the mini-event order and holidays.

export type Holiday = { id: string, nameKey: string, from: string, to: string } -- "MM-DD", UTC, inclusive

return {
	MiniEvery = 30 * 60, -- a mini event starts every 30 minutes…
	MiniLength = 5 * 60, -- …and lasts 5 minutes
	MiniOrder = { "GoldenHour", "TigerNight", "LanternRain" },
	GoldenHourCoins = 2,
	TigerNightSpirit = 2, -- spirit progress per title
	TigerNightSplash = 1.3,
	LanternCoins = 15, -- per lantern picked up in the lobby
	LanternEvery = 10, -- seconds between lantern drops during the rain
	LanternsPerDrop = 6,

	-- Weekly event: Saturday 18:00 Moscow = 15:00 UTC, for 2 hours. Effects are run by admins.
	WeeklyDay = 6, -- 0 = Sunday … 6 = Saturday (UTC)
	WeeklyHour = 15,
	WeeklyLength = 2 * 3600,

	Holidays = {
		{ id = "LunarNewYear", nameKey = "HOLIDAY_LUNAR_NEW_YEAR", from = "01-28", to = "02-12" },
		{ id = "LanternFestival", nameKey = "HOLIDAY_LANTERNS", from = "02-12", to = "02-14" },
		{ id = "DragonBoat", nameKey = "HOLIDAY_DRAGON_BOAT", from = "05-31", to = "06-02" },
	} :: { Holiday },
	HolidayXp = 2,

	AdminX3 = 3,
}
