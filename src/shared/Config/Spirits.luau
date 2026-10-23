--!strict
-- Shot spirits (GDD 10.2): unlocked by earning their titles, levelled by repeating them.
-- Spirits are cosmetic only: splash style, cue trail, announcer voice. Their levels add to the
-- dojo income (phase 8). Names are placeholders until checked.

export type Spirit = {
	id: string,
	nameKey: string,
	hanzi: string,
	titles: { string }, -- titles that feed this spirit
	secret: boolean?, -- hidden ("???") in the index until unlocked
	splash: string, -- splash style key when equipped
	trail: string, -- cue trail key (cosmetic)
	announcer: string, -- announcer voice key
}

return {
	Thresholds = { 1, 5, 20, 50, 150 }, -- titles needed for levels 1..5
	List = {
		{
			id = "Tiger",
			nameKey = "SPIRIT_TIGER",
			hanzi = "虎",
			titles = { "TIGER" },
			splash = "Tiger",
			trail = "Gold",
			announcer = "Tiger",
		},
		{
			id = "Carp",
			nameKey = "SPIRIT_CARP",
			hanzi = "鲤",
			titles = { "CARP" },
			splash = "Carp",
			trail = "Water",
			announcer = "Carp",
		},
		{
			id = "Panda",
			nameKey = "SPIRIT_PANDA",
			hanzi = "熊猫",
			titles = { "PANDA" },
			splash = "Panda",
			trail = "Bamboo",
			announcer = "Panda",
		},
		{
			id = "Dragon",
			nameKey = "SPIRIT_DRAGON",
			hanzi = "龙",
			titles = { "DRAGON" },
			splash = "Dragon",
			trail = "Fire",
			announcer = "Dragon",
		},
		{
			id = "Crane",
			nameKey = "SPIRIT_CRANE",
			hanzi = "鹤",
			titles = { "CRANE" },
			splash = "Crane",
			trail = "Cloud",
			announcer = "Crane",
		},
		{
			id = "Monkey",
			nameKey = "SPIRIT_MONKEY",
			hanzi = "猴",
			titles = { "MONKEY", "WHIRLWIND" },
			splash = "Monkey",
			trail = "Staff",
			announcer = "Monkey",
		},
		{
			id = "Serpent",
			nameKey = "SPIRIT_SERPENT",
			hanzi = "蛇",
			titles = { "SERPENT" },
			splash = "Serpent",
			trail = "Jade",
			announcer = "Serpent",
		},
		{
			id = "Phoenix",
			nameKey = "SPIRIT_PHOENIX",
			hanzi = "凤",
			titles = { "PHOENIX" },
			splash = "Phoenix",
			trail = "Flame",
			announcer = "Phoenix",
		},
		{
			id = "Heaven",
			nameKey = "SPIRIT_HEAVEN",
			hanzi = "天",
			titles = { "HEAVEN" },
			secret = true,
			splash = "Heaven",
			trail = "Light",
			announcer = "Heaven",
		},
	} :: { Spirit },
	DojoBonusPerLevel = 0.02, -- +2% dojo income per spirit level (phase 8)
}
