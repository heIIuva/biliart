--!strict
-- Pool simulation constants (SI units: meters, seconds). Tuned by feel in phase 1–2.
-- Table dimensions and pockets live in Pool/TableGeometry (per table variant).

local BALL_RADIUS = 0.028575 -- 57.15 mm diameter

return {
	StudsPerMeter = 6, -- TODO(phase 2): tune against avatar scale
	BallRadius = BALL_RADIUS,
	Gravity = 9.81,

	SlideFriction = 0.2,
	RollFriction = 0.01,
	SpinFriction = 0.044 * BALL_RADIUS,

	BallRestitution = 0.95,
	CushionRestitution = 0.78,

	MaxCueSpeed = 9.5, -- m/s at power = 1
	MaxTipOffset = 0.5, -- fraction of ball radius
	MaxElevation = math.rad(60),

	MaxShotSeconds = 15,
	RecordHz = 60,
}
