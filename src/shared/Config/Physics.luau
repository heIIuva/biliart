--!strict
-- Pool simulation constants (SI units: meters, seconds). Tuned by feel.
-- Table dimensions and pockets live in Pool/TableGeometry (per table variant).

local BALL_RADIUS = 0.028575 -- 57.15 mm diameter

return {
	StudsPerMeter = 6, -- TODO(phase 2): tune against avatar scale
	BallRadius = BALL_RADIUS,
	Gravity = 9.81,

	SlideFriction = 0.2,
	RollFriction = 0.01,
	-- Lever arm (meters) of the cloth friction resisting spin around the vertical axis:
	-- angular deceleration = 5 * SpinFriction * g / (2 * R^2).
	SpinFriction = 0.044 * BALL_RADIUS,

	BallRestitution = 0.95,
	CushionRestitution = 0.78,
	CushionFriction = 0.1, -- tangential friction at cushions: side spin changes the rebound angle

	MaxCueSpeed = 9.5, -- m/s at power = 1
	MaxTipOffset = 0.5, -- fraction of ball radius
	MaxElevation = math.rad(60),

	JumpRestitution = 0.2, -- share of the cue's downward speed the slate returns as vertical speed
	MinJumpSpeed = 0.3, -- slower vertical speed is absorbed: the ball stays on the cloth
	LandRestitution = 0.4,
	MinBounceSpeed = 0.25,
	RailHeight = 0.045, -- an airborne ball whose bottom is higher than this flies over the cushion
	RattleSpeed = 0.6, -- jaw hits slower than this also emit Rattle

	RackGap = 0.0006, -- spacing between racked balls; each ball is jittered within half of it

	SimHz = 240,
	RecordHz = 60, -- must divide SimHz
	MaxShotSeconds = 15,
	MaxEventsPerStep = 64, -- safety valve against pathological contact loops
}
