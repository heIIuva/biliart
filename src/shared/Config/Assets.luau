--!strict
-- All Sound/Image/Mesh asset IDs by key. 0 = placeholder: code must fall back (print stub, no sound).
-- Keep in sync with docs/ASSETS.md.

return {
	Sounds = {
		CueStrike = 0, -- cue tip hits the cue ball
		BallHit = 0, -- ball-ball click, volume scales with impact speed
		CushionHit = 0, -- ball thud on a cushion
		JawHit = 0, -- ball rattles on a pocket jaw
		Pocket = 0, -- ball drops into a pocket
		Land = 0, -- jumped ball lands on the cloth
	} :: { [string]: number },
	Images = {} :: { [string]: number },
	Meshes = {} :: { [string]: number },
}
