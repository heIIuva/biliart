--!strict
-- Chaos mode (GDD 12): 8-ball plus golden balls that hand out one-shot bonuses, and the Tiger
-- super shot meter. Glitch titles happen only here (never in ranked).

export type Bonus = {
	id: string,
	nameKey: string,
	target: "Self" | "Opponent", -- whose next shot it changes
	weight: number,
}

return {
	GoldenBalls = 2,
	Bonuses = {
		{ id = "NarrowPockets", nameKey = "CHAOS_NARROW", target = "Opponent", weight = 3 },
		{ id = "Fog", nameKey = "CHAOS_FOG", target = "Opponent", weight = 3 },
		{ id = "Earthquake", nameKey = "CHAOS_EARTHQUAKE", target = "Self", weight = 2 },
		{ id = "MoonJump", nameKey = "CHAOS_MOON_JUMP", target = "Self", weight = 2 },
	} :: { Bonus },
	EarthquakeShift = 0.04, -- max displacement of every ball (meters)
	MoonJumpRestitution = 0.55, -- instead of Physics.JumpRestitution
	MeterPerTitle = 0.34, -- three titles fill the Tiger meter
	SuperShotSpeed = 1.3, -- x max cue speed
	GlitchChance = 0.03, -- per legal shot in chaos mode
	BotLevel = "Medium",
}
