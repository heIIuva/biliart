--!strict
-- Speed pool (GDD 12): both players shoot at the same time with their own cue ball.
-- A pot scores for the player whose cue ball last touched that ball (directly or through a chain).

return {
	MatchSeconds = 180,
	SecondCueId = 16, -- player 2's cue ball (player 1 keeps id 0)
	EightPoints = 3,
	ScratchPenalty = 1,
	RespawnSeconds = 1,
	StateHz = 20, -- live state broadcasts per second
}
