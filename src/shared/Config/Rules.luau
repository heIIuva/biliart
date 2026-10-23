--!strict
-- 8-ball rule settings. Variants differ by data only (keyed by table variant).

export type Variant = {
	EightOnBreakWins: boolean, -- a pot of the 8 on a clean break wins the game
	BreakMinCushionBalls: number, -- a break without a pot is legal if this many object balls touch a cushion
	BreakFromKitchen: boolean, -- the breaker places the cue ball behind the head string
}

local STANDARD: Variant = {
	EightOnBreakWins = true,
	BreakMinCushionBalls = 4,
	BreakFromKitchen = true,
}

return {
	Variants = {
		Standard = STANDARD,
		Chinese8 = STANDARD, -- same rules; the table itself has narrower pockets
	} :: { [string]: Variant },

	TurnSeconds = 30,
	TimeoutPenaltySeconds = 10, -- each timeout of a player cuts their turn time by this
	MinTurnSeconds = 10,
}
