--!strict
-- Player data (GDD 10.1) on ProfileStore: session locking, template reconcile and migration,
-- autosave by ProfileStore. Sends a snapshot to the owner whenever it changes (batched).
-- Also owns currency and XP changes so every change is logged to analytics in one place.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Progression = require(Shared.Game.Progression)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)
local RateLimiter = require(Shared.Util.RateLimiter)
local Validate = require(Shared.Util.Validate)
local Strings = require(Shared.Config.Strings)
local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)
local AnalyticsService = require(script.Parent.AnalyticsService)

local STORE_NAME = "PlayerData_v1"
local SNAPSHOT_INTERVAL = 0.25

type Profile = {
	Data: Progression.PlayerData,
	AddUserId: (any, number) -> (),
	Reconcile: (any) -> (),
	EndSession: (any) -> (),
	IsActive: (any) -> boolean,
	OnSessionEnd: any,
	MessageHandler: (any, (any, () -> ()) -> ()) -> (),
	Save: (any) -> (),
}

local store = ProfileStore.New(STORE_NAME, Progression.template())
local profiles: { [Player]: Profile } = {}
local dirty: { [Player]: boolean } = {}

local DataService = {
	Loaded = Signal.new(), -- (player, data)
	LevelUp = Signal.new(), -- (player, level)
	Message = Signal.new(), -- (player, message): a message sent to the player's saved data
}

-- Sends a message to a player's saved data; delivered when (or as soon as) they are online.
function DataService.message(userId: number, message: { [string]: any })
	task.spawn(pcall, function()
		store:MessageAsync(tostring(userId), message)
	end)
end

-- Server-side text for things the client can't localize (kick messages).
local function localized(player: Player, key: string): string
	local entry = Strings[key]
	return if string.sub(player.LocaleId, 1, 2) == "ru" then entry.ru else entry.en
end

function DataService.get(player: Player): Progression.PlayerData?
	local profile = profiles[player]
	return if profile and profile:IsActive() then profile.Data else nil
end

-- Marks the player's data as changed: a snapshot goes to their client on the next batch.
function DataService.changed(player: Player)
	dirty[player] = true
end

-- Saves right away (after a purchase) instead of waiting for the autosave.
function DataService.save(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile:Save()
	end
end

function DataService.notify(player: Player, key: string, values: { [string]: any }?)
	local message: Remotes.Notification = { key = key, values = values }
	Remotes.Event("Notify"):FireClient(player, message)
end

-- Adds (or with a negative amount spends) coins or gems; false if the player can't afford it.
-- transactionType: an Enum.AnalyticsEconomyTransactionType name (Gameplay, Shop, IAP, TimedReward…).
function DataService.addCurrency(
	player: Player,
	currency: "coins" | "gems",
	amount: number,
	transactionType: string,
	sku: string?
): boolean
	local data = DataService.get(player)
	if not data or amount ~= amount or amount == 0 then
		return false
	end
	if data[currency] + amount < 0 then
		return false
	end
	data[currency] += amount
	AnalyticsService.economy(player, amount > 0, currency, math.abs(amount), data[currency], transactionType, sku)
	DataService.changed(player)
	return true
end

function DataService.addXp(player: Player, amount: number)
	local data = DataService.get(player)
	if not data or amount <= 0 then
		return
	end
	data.xp += amount
	local level = Progression.levelForXp(data.xp)
	if level > data.level then
		data.level = level
		AnalyticsService.progression(player, "Level", level)
		DataService.notify(player, "NOTIFY_LEVEL_UP", { level = level })
		DataService.LevelUp:Fire(player, level)
	end
	DataService.changed(player)
end

local function snapshot(data: Progression.PlayerData): { [string]: any }
	local copy = table.clone(data :: any)
	copy.purchases = nil -- receipts stay on the server
	copy.starterPackBought = data.purchases.starterPack
	return copy
end

local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	}) :: Profile?
	if not profile then
		player:Kick(localized(player, "DATA_LOAD_FAILED"))
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profile:MessageHandler(function(message, processed)
		if type(message) == "table" then
			DataService.Message:Fire(player, message)
		end
		processed()
	end)
	Progression.migrate(profile.Data :: any)
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		dirty[player] = nil
		if player.Parent == Players then
			player:Kick(localized(player, "DATA_SESSION_ENDED"))
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	local data = profile.Data
	if data.firstJoinTime == 0 then
		data.firstJoinTime = os.time()
	end
	DataService.changed(player)
	DataService.Loaded:Fire(player, data)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			profile.Data.lastOnlineTime = os.time()
			profile:EndSession()
		end
	end)
	Remotes.Event("TutorialDone").OnServerEvent:Connect(function(player)
		local data = DataService.get(player)
		if data and not data.tutorialDone then
			data.tutorialDone = true
			DataService.changed(player)
		end
	end)
	local settingsLimiter = RateLimiter.new(4, 2)
	Remotes.Event("SetSettings").OnServerEvent:Connect(function(player, payload)
		local data = DataService.get(player)
		local settings = if data and settingsLimiter:Allow(player)
			then Validate.settings(data.settings, payload)
			else nil
		if data and settings then
			data.settings = settings
			DataService.changed(player)
		end
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < SNAPSHOT_INTERVAL then
			return
		end
		elapsed = 0
		for player in dirty do
			dirty[player] = nil
			local data = DataService.get(player)
			if data then
				Remotes.Event("PlayerData"):FireClient(player, snapshot(data))
			end
		end
	end)
end

return DataService
