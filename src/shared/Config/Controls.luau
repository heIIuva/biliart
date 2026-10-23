--!strict
-- Aim, camera and input tuning (client).

return {
	CameraFov = 12, -- small FOV from far away: almost orthographic top-down view
	CameraTweenSeconds = 0.8,
	CameraWidthPadding = 1.35, -- room around the table for the power bar and the fine wheel
	CameraHeightPadding = 1.15,

	FineRadiansPerPixel = 0.0004, -- fine wheel
	WheelRadians = math.rad(0.25), -- mouse wheel step
	KeyRadiansPerSecond = math.rad(8), -- arrow keys
	MaxPullMeters = 0.35, -- PC: pull-back distance (table space) for full power
	MinPower = 0.02, -- releasing below this cancels the shot

	-- Aim guide lengths are fixed for now; cue stats come in phase 6 (never in ranked/tutorial).
	GuideObjectMeters = 0.3,
	GuideCueMeters = 0.18,

	CueLengthMeters = 1.45,
	CueTipGapMeters = 0.01,
	CuePullbackMeters = 0.25, -- visual pull-back at full power
	ShotResultTimeout = 5, -- seconds to wait for the server before unlocking the aim
}
