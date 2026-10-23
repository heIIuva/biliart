--!strict
-- Social features (GDD 15): friends bonus, invites with a reward for the inviter, group bonus,
-- codes, quick chat phrases and emotes. No free text is ever shown to other players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local QuickChat = require(Shared.Config.QuickChat)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Social = require(Shared.Config.Social)
local AnalyticsService = require(script.Parent.AnalyticsService)
local DataService = require(script.Parent.DataService)

local friendCount: { [Player]: number } = {}
local friendPairs: { [string]: boolean } = {} -- "a:b" with a < b
local chatLimiter = RateLimiter.new(Social.QuickChatPerMinute / 60, 3)
local codeLimiter = RateLimiter.new(0.2, 3)
local liveCodes: { [string]: { coins: number?, gems: number? } } = {} -- live config overrides (phase 11)

local SocialService = {}

local function pairKey(a: Player, b: Player): string
	local x, y = math.min(a.UserId, b.UserId), math.max(a.UserId, b.UserId)
	return `{x}:{y}`
end

local function recount()
	for _, player in Players:GetPlayers() do
		local count = 0
		for _, other in Players:GetPlayers() do
			if other ~= player and friendPairs[pairKey(player, other)] then
				count += 1
			end
		end
		friendCount[player] = count
	end
end

-- Match reward multiplier: +10% per friend on the server (capped).
function SocialService.rewardMultiplier(player: Player): number
	local bonus = math.min((friendCount[player] or 0) * Social.FriendBonusPerFriend, Social.FriendBonusMax)
	return 1 + bonus
end

function SocialService.setLiveCodes(codes: { [string]: { coins: number?, gems: number? } })
	liveCodes = codes
end

local function grant(player: Player, reward: { coins: number?, gems: number? }, sku: string)
	if reward.coins and reward.coins > 0 then
		DataService.addCurrency(player, "coins", reward.coins, "Onboarding", sku)
		DataService.notify(player, "NOTIFY_COINS", { amount = reward.coins })
	end
	if reward.gems and reward.gems > 0 then
		DataService.addCurrency(player, "gems", reward.gems, "Onboarding", sku)
		DataService.notify(player, "NOTIFY_GEMS", { amount = reward.gems })
	end
end

local function onPlayerAdded(player: Player)
	-- Friends: check every pair once (IsFriendsWith yields).
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local ok, friends = pcall(function()
				return player:IsFriendsWithAsync(other.UserId)
			end)
			if ok and friends then
				friendPairs[pairKey(player, other)] = true
			end
		end
	end
	recount()
	if (friendCount[player] or 0) > 0 then
		DataService.notify(player, "SOCIAL_FRIENDS_BONUS", {
			percent = math.round((SocialService.rewardMultiplier(player) - 1) * 100),
		})
	end
end

local function onDataLoaded(player: Player, data)
	-- Invited by a friend: reward the inviter once, through their saved data (they may be offline).
	local joinData = player:GetJoinData()
	local inviter = tonumber(joinData and joinData.LaunchData)
	local isNew = os.time() - data.firstJoinTime < 60 and data.stats.shots == 0
	if inviter and inviter ~= player.UserId and isNew then
		DataService.message(inviter, { kind = "InviteReward", invitee = player.UserId })
	end
	-- Group bonus, once.
	if Social.GroupId ~= 0 and not data.groupRewardClaimed then
		local ok, member = pcall(function()
			return player:IsInGroupAsync(Social.GroupId)
		end)
		if ok and member then
			data.groupRewardClaimed = true
			grant(player, Social.GroupReward, "GroupBonus")
		end
	end
end

local function onMessage(player: Player, message: { [string]: any })
	if message.kind == "InviteReward" then
		grant(player, Social.InviteReward, "InviteReward")
		DataService.notify(player, "SOCIAL_INVITE_REWARD")
	end
end

local function onRedeem(player: Player, raw: unknown)
	local data = DataService.get(player)
	if not codeLimiter:Allow(player) or not data or type(raw) ~= "string" or #raw > Social.MaxCodeLength then
		return
	end
	local code = string.upper((string.gsub(raw, "%s", "")))
	local reward = liveCodes[code] or Social.Codes[code]
	if not reward or data.redeemedCodes[code] then
		DataService.notify(player, "CODE_INVALID")
		return
	end
	data.redeemedCodes[code] = true
	grant(player, reward, `Code_{code}`)
	DataService.changed(player)
end

local function onQuickChat(player: Player, id: unknown)
	if not chatLimiter:Allow(player) or type(id) ~= "string" then
		return
	end
	for _, list in { QuickChat.Phrases, QuickChat.Emotes } do
		for _, entry in list do
			if entry.id == id then
				local message: Remotes.QuickChatMessage = { userId = player.UserId, id = id }
				Remotes.Event("QuickChatShown"):FireAllClients(message)
				AnalyticsService.custom(player, "QuickChat")
				return
			end
		end
	end
end

function SocialService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		friendCount[player] = nil
		chatLimiter:Forget(player)
		codeLimiter:Forget(player)
		task.defer(recount)
	end)
	DataService.Loaded:Connect(onDataLoaded)
	DataService.Message:Connect(onMessage)
	Remotes.Event("RedeemCode").OnServerEvent:Connect(onRedeem)
	Remotes.Event("QuickChat").OnServerEvent:Connect(onQuickChat)
end

return SocialService
