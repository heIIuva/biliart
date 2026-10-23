--!strict
-- Daily reward with a 7-day streak and daily/weekly quests (GDD 10.5). Days and weeks are UTC.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Game.Progression)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)

local REFRESH_SECONDS = 60
local limiter = RateLimiter.new(2, 4)

local QuestService = {}

-- A game event for quest progress: "wins", "pots", "spinPots", "matches", or "title" + titleId.
function QuestService.event(player: Player, kind: string, titleId: string?, amount: number?)
	local data = DataService.get(player)
	if data and Progression.questEvent(data, kind, titleId, amount) then
		DataService.changed(player)
	end
end

local function grant(player: Player, coins: number?, gems: number?, transactionType: string, sku: string)
	if coins and coins > 0 then
		DataService.addCurrency(player, "coins", coins, transactionType, sku)
		DataService.notify(player, "NOTIFY_COINS", { amount = coins })
	end
	if gems and gems > 0 then
		DataService.addCurrency(player, "gems", gems, transactionType, sku)
		DataService.notify(player, "NOTIFY_GEMS", { amount = gems })
	end
end

local function onClaimDaily(player: Player)
	local data = DataService.get(player)
	if not limiter:Allow(player) or not data then
		return
	end
	local day, daily = Progression.claimDaily(data.daily, Progression.dayIndex(os.time()))
	if not day then
		return
	end
	data.daily = daily
	local reward = Economy.DailyRewards[day]
	grant(player, reward.coins, reward.gems, "TimedReward", `Daily{day}`)
	DataService.changed(player)
end

local function onClaimQuest(player: Player, id: unknown)
	local data = DataService.get(player)
	if not limiter:Allow(player) or not data or type(id) ~= "string" then
		return
	end
	for _, list in { data.quests.daily, data.quests.weekly } do
		for _, state in list do
			local def = Progression.questDef(state.id)
			if state.id == id and def and not state.claimed and state.progress >= def.target then
				state.claimed = true
				grant(player, def.coins, def.gems, "Gameplay", `Quest_{id}`)
				DataService.changed(player)
				return
			end
		end
	end
end

function QuestService.Start()
	DataService.Loaded:Connect(function(player, data)
		if Progression.refreshQuests(data, player.UserId, os.time()) then
			DataService.changed(player)
		end
	end)
	Remotes.Event("ClaimDaily").OnServerEvent:Connect(onClaimDaily)
	Remotes.Event("ClaimQuest").OnServerEvent:Connect(onClaimQuest)
	Players.PlayerRemoving:Connect(function(player)
		limiter:Forget(player)
	end)
	task.spawn(function()
		while true do
			task.wait(REFRESH_SECONDS)
			for _, player in Players:GetPlayers() do
				local data = DataService.get(player)
				if data and Progression.refreshQuests(data, player.UserId, os.time()) then
					DataService.changed(player)
				end
			end
		end
	end)
end

return QuestService
