--!strict
-- Rewarded video ads (GDD 14). The client asks for an ad only after the player pressed a button
-- that names the reward. The server checks the daily limit and the context, never shows an ad
-- during the player's own turn, then plays the ad; the reward itself arrives as a developer
-- product receipt in ShopService.ProcessReceipt (channel AdReward). If ads fail, nothing breaks.

local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Ads = require(Shared.Config.Ads)
local Progression = require(Shared.Game.Progression)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Shop = require(Shared.Game.Shop)
local AnalyticsService = require(script.Parent.AnalyticsService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local limiter = RateLimiter.new(0.2, 2)
local views: { [Player]: { day: number, count: number } } = {}

-- Context checks: is there something for this ad to double right now?
local function contextOk(player: Player, placement: string): boolean
	local data = DataService.get(player)
	if not data then
		return false
	end
	if placement == "MatchX2" then
		return MatchService.lastMatchCoins(player) > 0
	elseif placement == "OfflineX2" then
		return data.dojo.pendingOffline > 0
	end
	return true
end

local function onRequest(player: Player, placement: unknown)
	if not limiter:Allow(player) or type(placement) ~= "string" then
		return
	end
	local config = Ads.Placements[placement]
	local product = if config then Shop.productByKey(config.product) else nil
	local today = Progression.dayIndex(os.time())
	local existing = views[player]
	local count = if existing and existing.day == today then existing else { day = today, count = 0 }
	views[player] = count
	local allowed = config ~= nil
		and product ~= nil
		and product.id ~= 0
		and count.count < Ads.DailyLimit
		and not MatchService.isPlayersTurn(player)
		and contextOk(player, placement)
	local shown = false
	if allowed and config and product then
		local ok, result = pcall(function()
			local reward = AdService:CreateAdRewardFromDevProductId(product.id)
			local placementId = if config.placementId ~= 0 then config.placementId else nil
			return AdService:ShowRewardedVideoAdAsync(player, reward, placementId)
		end)
		shown = ok and result == Enum.ShowAdResult.ShowCompleted
		if shown then
			count.count += 1
		end
		AnalyticsService.custom(player, if shown then `AdWatched_{placement}` else `AdFailed_{placement}`)
	end
	Remotes.Event("AdResult"):FireClient(player, { placement = placement, shown = shown })
end

local AdRewardService = {}

function AdRewardService.Start()
	Remotes.Event("RequestAd").OnServerEvent:Connect(onRequest)
	Players.PlayerRemoving:Connect(function(player)
		views[player] = nil
		limiter:Forget(player)
	end)
end

return AdRewardService
