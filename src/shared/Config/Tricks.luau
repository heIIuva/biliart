--!strict
-- Trick of the week (GDD 12): an absurd fixed layout; pot the target ball without scratching.
-- The week (UTC, from Monday) picks the trick. Every trick has a known solution, found by
-- tools/find_tricks.luau and checked by tests/chaos.spec.luau.

export type Trick = {
	id: string,
	nameKey: string,
	balls: { { number } }, -- { id, x, y } on the Standard table
	target: number,
	solution: { angle: number, power: number, spinX: number, spinY: number, elevation: number }?,
}

return {
	DailyAttempts = 10,
	FirstSolveCoins = 300,
	List = {
		{
			-- Behind a wall of stripes: go around it (or jump it).
			id = "GreatWall",
			nameKey = "TRICK_GREAT_WALL",
			balls = {
				{ 0, -0.7, 0 },
				{ 9, -0.5, -0.12 },
				{ 10, -0.5, -0.06 },
				{ 11, -0.5, 0 },
				{ 12, -0.5, 0.06 },
				{ 13, -0.5, 0.12 },
				{ 1, 0.85, 0.3 },
			},
			target = 1,
			solution = { angle = 0.24870941840919195, power = 0.29999999999999999, spinX = 0, spinY = 0, elevation = 0 },
		},
		{
			-- Two-rail bank into the far corner.
			id = "DragonBank",
			nameKey = "TRICK_DRAGON_BANK",
			balls = { { 0, -0.8, -0.4 }, { 1, -0.2, 0.35 }, { 8, 0, 0 }, { 9, 0.4, -0.1 } },
			target = 1,
			solution = { angle = 0.89884456477707964, power = 0.29999999999999999, spinX = 0, spinY = 0, elevation = 0 },
		},
		{
			-- The 8 sits on the pocket lip; sneak the 1 past it.
			id = "NeedleEye",
			nameKey = "TRICK_NEEDLE_EYE",
			balls = { { 0, 0.2, 0.2 }, { 1, 0.7, 0.42 }, { 8, 1.04, 0.48 }, { 9, 0.9, 0.2 } },
			target = 1,
			solution = { angle = 0.17016960206944715, power = 0.29999999999999999, spinX = 0, spinY = 0, elevation = 0 },
		},
	} :: { Trick },
}
