--!strict
-- Vertical replay for reels / TikTok (GDD 8). Safe zones are shares of the 9:16 frame that
-- the platforms cover with their own UI.

return {
	Aspect = 9 / 16, -- frame width / height
	SafeTop = 0.12,
	SafeBottom = 0.2,
	SafeRight = 0.15,
	TableMargin = 0.06, -- extra room around the table inside the frame
	CameraFov = 12,
	OfferSeconds = 8, -- the Clip button stays this long after a shot
	CinematicSeconds = 1.8, -- closing shot of the avatar
	WinEmote = "cheer", -- default Roblox emotes, until own animations exist
	FailEmote = "laugh",
}
