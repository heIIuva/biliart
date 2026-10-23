--!strict
-- Hype system tuning (GDD 7.3–7.4).

return {
	CurveMinElevation = math.rad(30), -- a "curved" (masse) shot needs this much cue elevation
	CurveMinDrift = 0.05, -- and this much sideways drift of the cue ball (meters)

	ComboScalePerLevel = 0.25, -- each title in a row makes the next splash 25% bigger/louder
	MaxCombo = 4,

	RarityMinShots = 500, -- below this many recorded shots no rarity % is shown
	FlushSeconds = 30, -- send local counters to MemoryStore this often
	RarityRefreshSeconds = 60,
	BackupSeconds = 600, -- copy MemoryStore counters to DataStore this often
	CounterTtlSeconds = 30 * 24 * 3600,

	ServerAnnounceTiers = { Epic = true, Legendary = true },
	CrossServerTiers = { Legendary = true },
	CrossServerCooldown = 10, -- seconds between cross-server announcements from one server

	SlowMoScale = 0.35, -- playback speed around the decisive moment
	SlowMoLead = 0.45, -- seconds before the decisive event
	SlowMoTail = 0.35,
	SplashSeconds = 2.2,
	MaxSplashWait = 3, -- the server holds the next turn at most this long for a splash
}
