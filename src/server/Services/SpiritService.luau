--!strict
-- Shot spirits (GDD 10.2): every title gives progress to its spirits; the first one unlocks it.
-- The equipped spirit only changes cosmetics (splash style, cue trail, announcer voice).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Progression = require(Shared.Game.Progression)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Spirits = require(Shared.Config.Spirits)
local DataService = require(script.Parent.DataService)

local limiter = RateLimiter.new(2, 4)

local function spiritDef(id: string): Spirits.Spirit?
	for _, spirit in Spirits.List do
		if spirit.id == id then
			return spirit
		end
	end
	return nil
end

local SpiritService = {}

function SpiritService.onTitle(player: Player, titleId: string)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.stats.titles[titleId] = (data.stats.titles[titleId] or 0) + 1
	for _, id in Progression.spiritsFor(titleId) do
		local state: { level: number, progress: number, skin: string } = data.spirits[id]
			or { level = 0, progress = 0, skin = "" }
		data.spirits[id] = state
		state.progress += 1
		local level = Progression.spiritLevel(state.progress)
		if level > state.level then
			local def = spiritDef(id) :: Spirits.Spirit
			if state.level == 0 then
				DataService.notify(player, "NOTIFY_SPIRIT_UNLOCKED", { name = def.nameKey })
				if data.equippedSpirit == "" then
					data.equippedSpirit = id
				end
			else
				DataService.notify(player, "NOTIFY_SPIRIT_LEVEL", { name = def.nameKey, level = level })
			end
			state.level = level
		end
	end
	DataService.changed(player)
end

-- Sum of all spirit levels (feeds the dojo income bonus).
function SpiritService.totalLevels(player: Player): number
	local data = DataService.get(player)
	local total = 0
	if data then
		for _, state in data.spirits do
			total += state.level
		end
	end
	return total
end

function SpiritService.Start()
	Remotes.Event("EquipSpirit").OnServerEvent:Connect(function(player, id)
		local data = DataService.get(player)
		if not limiter:Allow(player) or not data or type(id) ~= "string" then
			return
		end
		local state = data.spirits[id]
		if state and state.level > 0 then
			data.equippedSpirit = id
			DataService.changed(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		limiter:Forget(player)
	end)
end

return SpiritService
