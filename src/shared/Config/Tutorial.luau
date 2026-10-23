--!strict
-- First-session tutorial (GDD 9.5). The first break is rigged: a fixed rack and, for any power at or
-- above MinPower, the server plays BreakShot instead, which is known to give TIGER
-- (found with tools/find_scenarios.luau, checked by tests/hype.spec.luau).

return {
	RackSeed = 1,
	CueX = -0.56, -- head spot of the Standard table (meters)
	CueY = 0,
	MinPower = 0.3,
	BreakShot = { angle = 0, power = 0.9, spinX = 0, spinY = 0, elevation = 0 },
	BotLevel = "Easy",
	TableId = "table1",
	Hints = { "TUTORIAL_AIM", "TUTORIAL_POWER", "TUTORIAL_SPIN", "TUTORIAL_BALL_IN_HAND" },
}
