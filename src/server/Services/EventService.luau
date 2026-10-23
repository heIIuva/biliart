--!strict
-- Events (GDD 16): mini events every 30 minutes (Golden hour, Tiger night, Lantern rain), the
-- weekly event run by admins, holidays by date. Other services ask for the current multipliers.
-- Admin commands come through their own remote and are checked against Config.Admins on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Admins = require(Shared.Config.Admins)
local EventSchedule = require(Shared.Game.Events)
local Events = require(Shared.Config.Events)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local DataService = require(script.Parent.DataService)
local LiveConfigService = require(script.Parent.LiveConfigService)

export type AdminEffect = "AllTiger" | "GoldenRain" | "TripleRewards"

local LOBBY_CENTER = Vector3.new(0, 0, -15)
local LOBBY_RADIUS = 40
local LANTERN_LIFETIME = 20

local admin: { [string]: number } = {} -- effect -> os.time() it ends
local adminLimiter = RateLimiter.new(1, 3)
local lanternFolder: Folder
local lastState = ""

local EventService = {}

local function mini(): EventSchedule.Mini?
	return EventSchedule.mini(os.time(), LiveConfigService.get().miniOrder)
end

local function adminActive(effect: AdminEffect): boolean
	return (admin[effect] or 0) > os.time()
end

function EventService.coinMultiplier(): number
	local m = mini()
	local multiplier = if m and m.id == "GoldenHour" then Events.GoldenHourCoins else 1
	if adminActive("TripleRewards") then
		multiplier *= Events.AdminX3
	end
	return multiplier
end

function EventService.spiritMultiplier(): number
	local m = mini()
	return if m and m.id == "TigerNight" then Events.TigerNightSpirit else 1
end

function EventService.xpMultiplier(): number
	local holiday = EventSchedule.holiday(os.time(), LiveConfigService.get().holidays)
	return if holiday then Events.HolidayXp else 1
end

function EventService.dojoMultiplier(_player: Player): number
	return if adminActive("TripleRewards") then Events.AdminX3 else 1
end

-- "All shots are tiger shots" during the admin event.
function EventService.allTiger(): boolean
	return adminActive("AllTiger")
end

local function state(): { [string]: any }
	local now = os.time()
	local m = mini()
	local nextAt, nextId = EventSchedule.nextMini(now, LiveConfigService.get().miniOrder)
	local holiday = EventSchedule.holiday(now, LiveConfigService.get().holidays)
	local effects = {}
	for effect, ends in admin do
		if ends > now then
			effects[effect] = ends
		end
	end
	return {
		mini = if m then { id = m.id, endsAt = m.endsAt } else nil,
		nextMini = { at = nextAt, id = nextId },
		weekly = { start = EventSchedule.weeklyStart(now), active = EventSchedule.weeklyActive(now) },
		holiday = if holiday then holiday.nameKey else nil,
		admin = effects,
	}
end

local function broadcast(force: boolean)
	local s = state()
	local key = `{s.mini and s.mini.id or ""}|{s.holiday or ""}|{next(s.admin) or ""}|{s.weekly.active}`
	if force or key ~= lastState then
		lastState = key
		Remotes.Event("EventState"):FireAllClients(s)
	end
end

-- Lantern rain / golden rain: pickups fall in the lobby; the first player to touch one gets coins.
local function dropLanterns(count: number, golden: boolean)
	for _ = 1, count do
		local angle, distance = math.random() * 2 * math.pi, math.random() * LOBBY_RADIUS
		local position = LOBBY_CENTER + Vector3.new(math.cos(angle) * distance, 3, math.sin(angle) * distance)
		local lantern = Instance.new("Part")
		lantern.Name = if golden then "GoldenBall" else "Lantern"
		lantern.Shape = Enum.PartType.Ball
		lantern.Size = Vector3.one * 2
		lantern.Anchored = true
		lantern.CanCollide = false
		lantern.Material = Enum.Material.Neon
		lantern.Color = if golden then Color3.fromRGB(255, 200, 40) else Color3.fromRGB(230, 40, 30)
		lantern.Position = position
		local taken = false
		lantern.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			if taken or not player or not DataService.get(player) then
				return
			end
			taken = true
			lantern:Destroy()
			local coins = Events.LanternCoins * EventService.coinMultiplier()
			DataService.addCurrency(player, "coins", coins, "Gameplay", if golden then "GoldenRain" else "LanternRain")
			DataService.notify(player, "NOTIFY_COINS", { amount = coins })
		end)
		lantern.Parent = lanternFolder
		task.delay(LANTERN_LIFETIME, function()
			if lantern.Parent then
				lantern:Destroy()
			end
		end)
	end
end

local function onAdmin(player: Player, payload: unknown)
	if not adminLimiter:Allow(player) or not table.find(Admins.UserIds, player.UserId) or type(payload) ~= "table" then
		return
	end
	local raw = payload :: { [unknown]: unknown }
	local effect, minutes = raw.effect, raw.minutes
	if
		(effect == "AllTiger" or effect == "GoldenRain" or effect == "TripleRewards")
		and type(minutes) == "number"
		and minutes >= 0
		and minutes <= 180
	then
		admin[effect :: string] = os.time() + math.floor(minutes) * 60
		Remotes.Event("Announcement"):FireAllClients({
			playerName = player.DisplayName,
			titleId = `ADMIN_{string.upper(effect :: string)}`,
			crossServer = false,
		})
		broadcast(true)
	end
end

function EventService.Init()
	lanternFolder = Instance.new("Folder")
	lanternFolder.Name = "Lanterns"
	lanternFolder.Parent = Workspace
end

function EventService.Start()
	Remotes.Event("AdminCommand").OnServerEvent:Connect(onAdmin)
	Players.PlayerAdded:Connect(function(player)
		Remotes.Event("EventState"):FireClient(player, state())
	end)
	task.spawn(function()
		local sinceDrop = 0
		while true do
			task.wait(1)
			broadcast(false)
			sinceDrop += 1
			local m = mini()
			if sinceDrop >= Events.LanternEvery then
				if m and m.id == "LanternRain" then
					sinceDrop = 0
					dropLanterns(Events.LanternsPerDrop, false)
				elseif adminActive("GoldenRain") then
					sinceDrop = 0
					dropLanterns(Events.LanternsPerDrop, true)
				end
			end
		end
	end)
end

return EventService
