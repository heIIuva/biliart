--!strict
-- Cues (GDD 10.3). Stats apply in casual matches only; ranked and the tutorial use Base stats.
-- aim: aim guide length multiplier; spin: share of the max tip offset reachable;
-- power: share of the max cue speed; time: extra turn seconds.

export type Cue = {
	id: string,
	nameKey: string,
	price: number, -- coins; 0 = owned from the start
	aim: number,
	spin: number,
	power: number,
	time: number,
	minLevel: number,
}

return {
	Base = "Base",
	List = {
		{ id = "Base", nameKey = "CUE_BASE", price = 0, aim = 1, spin = 0.8, power = 0.9, time = 0, minLevel = 1 },
		{
			id = "Bamboo",
			nameKey = "CUE_BAMBOO",
			price = 500,
			aim = 1.15,
			spin = 0.85,
			power = 0.93,
			time = 1,
			minLevel = 3,
		},
		{
			id = "Lantern",
			nameKey = "CUE_LANTERN",
			price = 2000,
			aim = 1.3,
			spin = 0.9,
			power = 0.96,
			time = 2,
			minLevel = 8,
		},
		{
			id = "Jade",
			nameKey = "CUE_JADE",
			price = 6000,
			aim = 1.45,
			spin = 0.95,
			power = 0.98,
			time = 3,
			minLevel = 15,
		},
		{
			id = "Dragon",
			nameKey = "CUE_DRAGON",
			price = 15000,
			aim = 1.6,
			spin = 1,
			power = 1,
			time = 5,
			minLevel = 25,
		},
	} :: { Cue },
}
