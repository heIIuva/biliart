--!strict
-- PvP, King of the table and social features (GDD 9.2, 12, 15). No wagering: every reward is a
-- fixed value the game pays, never a pot from the players.

export type Reward = { coins: number?, gems: number? }

return {
	QueueSeconds = 20, -- no human opponent this long -> offer the bot
	PvpRewards = { win = 50, loss = 10 },
	RankedRewards = { win = 60, loss = 12 },
	RatingK = 32, -- Elo K-factor
	RatingStart = 1000,

	KingDefenseCoins = 40, -- paid to the king for every defense
	KingNextMatchDelay = 5,

	FriendBonusPerFriend = 0.1, -- +10% match rewards per friend on the server
	FriendBonusMax = 0.3,
	InviteReward = { coins = 300, gems = 5 } :: Reward, -- to the inviter when a new friend joins via the invite
	GroupId = 0, -- Roblox group id; 0 = no group bonus yet (set when the group exists)
	GroupReward = { coins = 0, gems = 10 } :: Reward,

	-- Codes: also overridable from live config (phase 11). Upper case.
	Codes = {
		HUHU = { coins = 250 },
	} :: { [string]: Reward },
	MaxCodeLength = 24,
	QuickChatPerMinute = 10,
}
