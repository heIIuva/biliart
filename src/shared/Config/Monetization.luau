--!strict
-- Game passes and developer products (GDD 13). id = 0 is a placeholder: create the pass/product in
-- the Creator Dashboard and paste its id here. Items with id 0 show in the shop but can't be bought.
-- REMINDER: if anything random is ever sold for Robux (directly or via Robux-bought currency),
-- show odds in % (sum = 100) before purchase and respect
-- PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted.
-- No item here is random and no currency is ever wagered.

export type Pass = { key: string, id: number, nameKey: string }
export type Product = {
	key: string,
	id: number,
	nameKey: string,
	coins: number?,
	gems: number?,
	boost: string?, -- "Coins" | "Dojo": x2 for `minutes`
	minutes: number?,
	serverHype: boolean?, -- x2 match rewards and bigger splashes for everyone on the server
	cosmetic: { category: string, id: string }?, -- unlocks a skin
	once: boolean?, -- starter pack: one purchase per player
	giftable: boolean?,
	adReward: string?, -- also granted by a rewarded ad for this placement
	hidden: boolean?, -- not listed in the shop (ad-only effect that needs context)
}

return {
	Passes = {
		{ key = "VIP", id = 0, nameKey = "PASS_VIP" }, -- x2 match coins, 24 h offline cap, tag, VIP splash
		{ key = "DojoX2", id = 0, nameKey = "PASS_DOJO_X2" },
		{ key = "AutoCollect", id = 0, nameKey = "PASS_AUTO_COLLECT" },
		{ key = "TigerTable", id = 0, nameKey = "PASS_TIGER_TABLE" }, -- cosmetic + small dojo income
	} :: { Pass },
	TigerTableBonus = 0.05,
	Products = {
		{ key = "Gems100", id = 0, nameKey = "PRODUCT_GEMS_100", gems = 100 },
		{ key = "Gems550", id = 0, nameKey = "PRODUCT_GEMS_550", gems = 550 },
		{ key = "Coins5000", id = 0, nameKey = "PRODUCT_COINS_5000", coins = 5000 },
		{ key = "Starter", id = 0, nameKey = "PRODUCT_STARTER", coins = 3000, gems = 150, once = true },
		{
			key = "BoostCoins30",
			id = 0,
			nameKey = "PRODUCT_BOOST_COINS",
			boost = "Coins",
			minutes = 30,
			giftable = true,
		},
		{ key = "BoostDojo30", id = 0, nameKey = "PRODUCT_BOOST_DOJO", boost = "Dojo", minutes = 30, giftable = true },
		{ key = "ServerHype", id = 0, nameKey = "PRODUCT_SERVER_HYPE", serverHype = true, minutes = 15 },
		{
			key = "CueGold",
			id = 0,
			nameKey = "SKIN_CUE_GOLD",
			cosmetic = { category = "cues", id = "GoldSkin" },
			giftable = true,
		},
		{
			key = "ClothJade",
			id = 0,
			nameKey = "SKIN_CLOTH_JADE",
			cosmetic = { category = "tables", id = "Jade" },
			giftable = true,
		},
		{
			key = "AnnouncerOpera",
			id = 0,
			nameKey = "SKIN_ANNOUNCER_OPERA",
			cosmetic = { category = "announcers", id = "Opera" },
			giftable = true,
		},
		{
			key = "SplashFirework",
			id = 0,
			nameKey = "SKIN_SPLASH_FIREWORK",
			cosmetic = { category = "splashSkins", id = "Firework" },
			giftable = true,
		},
		-- Rewarded-ad products (sold in the shop too, as Roblox requires).
		{
			key = "DojoBoost10",
			id = 0,
			nameKey = "PRODUCT_DOJO_BOOST_10",
			boost = "Dojo",
			minutes = 10,
			adReward = "DojoBoost",
		},
		{ key = "MatchDouble", id = 0, nameKey = "PRODUCT_MATCH_DOUBLE", adReward = "MatchX2", hidden = true },
		{ key = "OfflineDouble", id = 0, nameKey = "PRODUCT_OFFLINE_DOUBLE", adReward = "OfflineX2", hidden = true },
		{ key = "TrickRetry", id = 0, nameKey = "PRODUCT_TRICK_RETRY", adReward = "TrickRetry", hidden = true },
	} :: { Product },
}
