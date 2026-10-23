--!strict
-- Cues (GDD 10.3): bought with coins, equipped from the cue menu. Stats apply in casual matches;
-- ranked matches and the tutorial use the base cue for everyone (no pay-to-win).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Cues = require(Shared.Config.Cues)
local Progression = require(Shared.Game.Progression)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)

local limiter = RateLimiter.new(2, 4)

local CueService = {}

-- Stats of the cue the player uses in this match.
function CueService.stats(player: Player?, baseOnly: boolean): Cues.Cue
	local data = if player then DataService.get(player) else nil
	if baseOnly or not data then
		return Progression.cue(Cues.Base)
	end
	return Progression.cue(data.equipped.cue)
end

local function onBuy(player: Player, id: unknown)
	local data = DataService.get(player)
	if not limiter:Allow(player) or not data or type(id) ~= "string" then
		return
	end
	local cue = Progression.cue(id)
	if cue.id ~= id or data.cosmetics.cues[id] then
		return
	end
	if data.level < cue.minLevel then
		DataService.notify(player, "NOTIFY_LEVEL_LOCKED", { level = cue.minLevel })
		return
	end
	if not DataService.addCurrency(player, "coins", -cue.price, "Shop", `Cue_{id}`) then
		DataService.notify(player, "NOTIFY_NOT_ENOUGH")
		return
	end
	data.cosmetics.cues[id] = true
	data.equipped.cue = id
	DataService.changed(player)
end

local function onEquip(player: Player, id: unknown)
	local data = DataService.get(player)
	if limiter:Allow(player) and data and type(id) == "string" and data.cosmetics.cues[id] then
		data.equipped.cue = id
		DataService.changed(player)
	end
end

function CueService.Start()
	Remotes.Event("BuyCue").OnServerEvent:Connect(onBuy)
	Remotes.Event("EquipCue").OnServerEvent:Connect(onEquip)
	Players.PlayerRemoving:Connect(function(player)
		limiter:Forget(player)
	end)
end

return CueService
