--!strict
-- Bot difficulty: how many shot variants it tries and how precisely it executes the chosen one.

export type Level = {
	Powers: { number }, -- shot powers tried for every candidate
	SpinsY: { number }, -- follow/draw variants (tip offset, fraction of radius)
	MaxCutDegrees: number, -- skip cuts thinner than this
	AngleNoiseDegrees: number, -- execution error (standard deviation)
	PowerNoise: number, -- relative power error (standard deviation)
	BreakPower: number,
	ThinkSeconds: { number }, -- min, max time the bot "thinks"
}

return {
	Levels = {
		Easy = {
			Powers = { 0.45 },
			SpinsY = { 0 },
			MaxCutDegrees = 55,
			AngleNoiseDegrees = 1.6,
			PowerNoise = 0.15,
			BreakPower = 0.8,
			ThinkSeconds = { 1, 2 },
		},
		Medium = {
			Powers = { 0.35, 0.6 },
			SpinsY = { 0, -0.25 },
			MaxCutDegrees = 65,
			AngleNoiseDegrees = 0.6,
			PowerNoise = 0.08,
			BreakPower = 0.9,
			ThinkSeconds = { 1, 2.5 },
		},
		Hard = {
			Powers = { 0.3, 0.5, 0.75 },
			SpinsY = { 0, 0.3, -0.3 },
			MaxCutDegrees = 75,
			AngleNoiseDegrees = 0.15,
			PowerNoise = 0.03,
			BreakPower = 1,
			ThinkSeconds = { 1.5, 3 },
		},
	} :: { [string]: Level },
	PlacementDistance = 0.25, -- ball in hand: cue ball this far behind the ghost ball (meters)
	YieldEverySeconds = 0.005, -- planning work per frame before yielding
}
