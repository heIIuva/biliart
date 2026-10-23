--!strict
-- Rewarded video (GDD 14). Rewards are non-random developer products that are also sold in the
-- shop; ads only play after the player presses a button that names the reward, never during the
-- player's own turn, and never block progress. Placement ids: 0 = none (optional in the API).

return {
	DailyLimit = 8, -- rewarded ads per player per UTC day
	Placements = {
		MatchX2 = { product = "MatchDouble", placementId = 0 }, -- result screen: x2 match reward
		OfflineX2 = { product = "OfflineDouble", placementId = 0 }, -- "while you were away": x2
		DojoBoost = { product = "DojoBoost10", placementId = 0 }, -- x2 dojo income for 10 minutes
		TrickRetry = { product = "TrickRetry", placementId = 0 }, -- one more trick-of-the-week attempt
	} :: { [string]: { product: string, placementId: number } },
}
