--!strict
-- Title statistics and announcements (GDD 7.3–7.5).
-- Counters accumulate locally and are flushed to a MemoryStore sorted map every FlushSeconds
-- (atomic increments shared by all servers); a DataStore copy is kept as a long-term backup.
-- Any MemoryStore/DataStore/MessagingService failure only hides the rarity % or the announcement.

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Hype = require(Shared.Config.Hype)
local Remotes = require(Shared.Net.Remotes)
local Titles = require(Shared.Config.Titles)

local STORE_NAME = "HypeStats"
local TOTAL_KEY = "shots"
local CROSS_SERVER_TOPIC = "HypeLegendary"

local pending: { [string]: number } = {} -- local increments not flushed yet
local totals: { [string]: number } = {} -- last known global counts
local lastCrossServer = 0

local HypeService = {}

local function titleKey(id: string): string
	return "title:" .. id
end

-- GetSortedMap throws in a place that was never published (Studio); the loop must survive that.
local function sortedMap(): MemoryStoreSortedMap?
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap(STORE_NAME)
	end)
	return if ok then map else nil
end

local function flush()
	local map = sortedMap()
	if not map then
		return
	end
	for key, delta in pending do
		pending[key] = nil
		local ok = pcall(function()
			map:UpdateAsync(key, function(old)
				return (tonumber(old) or 0) + delta
			end, Hype.CounterTtlSeconds)
		end)
		if not ok then
			pending[key] = (pending[key] or 0) + delta -- retry on the next flush
		end
	end
end

local function refresh()
	local map = sortedMap()
	if not map then
		return
	end
	local backup = DataStoreService:GetDataStore(STORE_NAME)
	local keys = { TOTAL_KEY }
	for _, title in Titles do
		table.insert(keys, titleKey(title.id))
	end
	for _, key in keys do
		local ok, value = pcall(function()
			return map:GetAsync(key)
		end)
		if ok and value == nil then
			-- Expired or brand-new map: fall back to the long-term copy.
			ok, value = pcall(function()
				return backup:GetAsync(key)
			end)
		end
		if ok and tonumber(value) then
			totals[key] = tonumber(value) :: number
		end
	end
end

local function backupToDataStore()
	local backup = DataStoreService:GetDataStore(STORE_NAME)
	for key, value in totals do
		pcall(function()
			backup:SetAsync(key, value)
		end)
	end
end

-- Counts one shot (and its title, if any) towards the global statistics.
function HypeService.recordShot(titleId: string?)
	pending[TOTAL_KEY] = (pending[TOTAL_KEY] or 0) + 1
	if titleId then
		local key = titleKey(titleId)
		pending[key] = (pending[key] or 0) + 1
	end
end

-- Percent of all shots that earned this title, or nil while there is too little data.
function HypeService.rarity(titleId: string): number?
	local shots = totals[TOTAL_KEY]
	local count = totals[titleKey(titleId)]
	if not shots or shots < Hype.RarityMinShots or not count then
		return nil
	end
	return count / shots * 100
end

function HypeService.announce(playerName: string, title: Titles.Title)
	if not Hype.ServerAnnounceTiers[title.rarityTier] then
		return
	end
	local message: Remotes.Announcement = { playerName = playerName, titleId = title.id, crossServer = false }
	Remotes.Event("Announcement"):FireAllClients(message)
	if Hype.CrossServerTiers[title.rarityTier] and os.clock() - lastCrossServer >= Hype.CrossServerCooldown then
		lastCrossServer = os.clock()
		task.spawn(pcall, function()
			MessagingService:PublishAsync(CROSS_SERVER_TOPIC, { playerName = playerName, titleId = title.id })
		end)
	end
end

function HypeService.Start()
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(CROSS_SERVER_TOPIC, function(message)
				local data = message.Data
				if type(data) == "table" and type(data.playerName) == "string" and type(data.titleId) == "string" then
					local announcement: Remotes.Announcement =
						{ playerName = data.playerName, titleId = data.titleId, crossServer = true }
					Remotes.Event("Announcement"):FireAllClients(announcement)
				end
			end)
		end)
	end)
	task.spawn(function()
		refresh()
		local sinceRefresh, sinceBackup = 0, 0
		while true do
			task.wait(Hype.FlushSeconds)
			flush()
			sinceRefresh += Hype.FlushSeconds
			sinceBackup += Hype.FlushSeconds
			if sinceRefresh >= Hype.RarityRefreshSeconds then
				sinceRefresh = 0
				refresh()
			end
			if sinceBackup >= Hype.BackupSeconds then
				sinceBackup = 0
				backupToDataStore()
			end
		end
	end)
end

return HypeService
