--!strict
-- Idle dojo (GDD 11). Income per second =
--   sum(table base income x table level)
--   x (1 + spirit levels x Spirits.DojoBonusPerLevel)
--   x (1 + rebirths x RebirthBonus)
--   x (1 + decor bonuses) x other multipliers (game pass, boosts, events, King of the table).

export type TableSlot = { id: string, baseIncome: number, price: number, upgradeGrowth: number, maxLevel: number }
export type Decor = { id: string, nameKey: string, price: number, bonus: number }
export type Rebirth = { coins: number, titles: { [string]: number }, ranked: boolean }

return {
	Tables = {
		{ id = "T1", baseIncome = 1, price = 50, upgradeGrowth = 1.55, maxLevel = 10 },
		{ id = "T2", baseIncome = 3, price = 400, upgradeGrowth = 1.6, maxLevel = 10 },
		{ id = "T3", baseIncome = 8, price = 2500, upgradeGrowth = 1.65, maxLevel = 10 },
		{ id = "T4", baseIncome = 20, price = 12000, upgradeGrowth = 1.7, maxLevel = 10 },
		{ id = "T5", baseIncome = 50, price = 60000, upgradeGrowth = 1.75, maxLevel = 10 },
		{ id = "T6", baseIncome = 130, price = 300000, upgradeGrowth = 1.8, maxLevel = 10 },
	} :: { TableSlot },
	Decor = {
		{ id = "Lanterns", nameKey = "DECOR_LANTERNS", price = 1500, bonus = 0.05 },
		{ id = "Statues", nameKey = "DECOR_STATUES", price = 20000, bonus = 0.1 },
		{ id = "Gong", nameKey = "DECOR_GONG", price = 150000, bonus = 0.15 },
	} :: { Decor },
	RebirthBonus = 0.5, -- +50% income per rebirth, forever
	-- Requirement for the next rebirth (index = rebirths done + 1; the last one repeats with coins x2).
	Rebirths = {
		{ coins = 100000, titles = { TIGER = 3 }, ranked = false },
		{ coins = 500000, titles = { DRAGON = 1 }, ranked = true },
		{ coins = 2000000, titles = { PHOENIX = 1 }, ranked = false },
	} :: { Rebirth },
	OfflineCapHours = 8,
	OfflineCapHoursVip = 24,
	OfflineRate = 0.5, -- share of the online income earned while away
	KingBonus = 0.25, -- while holding the King table
	PlotCount = 12,
	PlotRingRadius = 95, -- studs from the lobby center
	PlotSize = 34,
}
