--!strict
-- Rewards and progression numbers (GDD 10). No wagering: every reward is a fixed value the game pays.

return {
	StartingCoins = 100,
	MatchRewards = { -- coins for finishing a match against the bot
		Easy = { win = 20, loss = 5 },
		Medium = { win = 35, loss = 8 },
		Hard = { win = 60, loss = 12 },
	} :: { [string]: { win: number, loss: number } },
	Xp = { Pot = 2, Title = 10, Win = 50, Loss = 15 },
	LevelBase = 100, -- xp from level n to n+1 = LevelBase * n ^ LevelExponent
	LevelExponent = 1.5,
	MaxLevel = 100,
	DailyRewards = { -- 7-day cycle, day 1 first
		{ coins = 50 },
		{ coins = 75 },
		{ coins = 100 },
		{ gems = 5 },
		{ coins = 150 },
		{ coins = 200 },
		{ gems = 20 },
	} :: { { coins: number?, gems: number? } },
	FriendBonusPerFriend = 0.1, -- phase 7
	FriendBonusMax = 0.3,
}
