--!strict
-- Thin wrapper over Roblox AnalyticsService (GDD 18). Every call is pcall-wrapped: analytics must
-- never break gameplay. Funnel steps are logged once per player per session (persisted with
-- player data in phase 6).

local Analytics = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)

local FUNNEL = {
	Joined = 1,
	SatAtTable = 2,
	FirstShot = 3,
	FirstTiger = 4,
	MatchFinished = 5,
	OpenedDojo = 6,
}

local logged: { [Player]: { [number]: boolean } } = {}

local AnalyticsService = {}

AnalyticsService.Funnel = FUNNEL

function AnalyticsService.funnel(player: Player, step: number, stepName: string)
	local done = logged[player]
	if not done then
		done = {}
		logged[player] = done
	end
	if done[step] then
		return
	end
	done[step] = true
	pcall(function()
		Analytics:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

function AnalyticsService.custom(player: Player, eventName: string, value: number?)
	pcall(function()
		Analytics:LogCustomEvent(player, eventName, value or 1)
	end)
end

function AnalyticsService.Start()
	local limiter = RateLimiter.new(0.5, 3)
	for _, name in { "ClipOpened", "ClipScreenshot" } do
		Remotes.Event(name).OnServerEvent:Connect(function(player)
			if limiter:Allow(player) then
				AnalyticsService.custom(player, name)
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		AnalyticsService.funnel(player, FUNNEL.Joined, "Joined")
	end)
	Players.PlayerRemoving:Connect(function(player)
		logged[player] = nil
	end)
end

return AnalyticsService
