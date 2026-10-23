--!strict
-- Global leaderboards on OrderedDataStores (GDD 10.4) and the physical boards in the lobby.
-- Boards: wins, ranked rating (phase 7), dojo income (phase 8), shot of the day (best title
-- priority per UTC day). The server sends top lists; clients draw them (localized titles).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Progression = require(Shared.Game.Progression)
local Remotes = require(Shared.Net.Remotes)

local REFRESH_SECONDS = 90
local TOP = 10

export type BoardId = "Wins" | "Rating" | "Dojo" | "ShotOfDay" | "Trick"

local BOARDS: { BoardId } = { "Wins", "ShotOfDay", "Dojo", "Rating", "Trick" }
local ASCENDING: { [string]: boolean } = { Trick = true } -- fewest attempts first
local POSITIONS = { -- lobby, facing the spawn
	Wins = Vector3.new(-18, 0, 14),
	ShotOfDay = Vector3.new(-6, 0, 20),
	Dojo = Vector3.new(6, 0, 20),
	Rating = Vector3.new(18, 0, 14),
	Trick = Vector3.new(28, 0, 2),
}

local names: { [number]: string } = {}
local latest: { [string]: { Remotes.LeaderboardRow } } = {}

local function storeName(board: BoardId): string
	if board == "ShotOfDay" then
		return `LB_ShotOfDay_{Progression.dayIndex(os.time())}`
	elseif board == "Trick" then
		return `LB_Trick_{Progression.weekIndex(os.time())}`
	end
	return `LB_{board}`
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else tostring(userId)
	names[userId] = result
	return result
end

local LeaderboardService = {}

-- Records a score. `keepBest`: only raise it (shot of the day); otherwise overwrite.
function LeaderboardService.submit(board: BoardId, player: Player, score: number, keepBest: boolean?)
	names[player.UserId] = player.DisplayName
	task.spawn(pcall, function()
		local store = DataStoreService:GetOrderedDataStore(storeName(board))
		local value = math.floor(score)
		if keepBest then
			store:UpdateAsync(tostring(player.UserId), function(old)
				return math.max(tonumber(old) or 0, value)
			end)
		else
			store:SetAsync(tostring(player.UserId), value)
		end
	end)
end

local function refresh()
	for _, board: BoardId in BOARDS do
		local ok, pages = pcall(function()
			return DataStoreService:GetOrderedDataStore(storeName(board)):GetSortedAsync(ASCENDING[board] == true, TOP)
		end)
		if ok and pages then
			local rows: { Remotes.LeaderboardRow } = {}
			for rank, entry in pages:GetCurrentPage() do
				local userId = tonumber(entry.key) or 0
				table.insert(rows, { rank = rank, name = nameOf(userId), score = entry.value })
			end
			latest[board] = rows
		end
	end
	Remotes.Event("Leaderboards"):FireAllClients(latest)
end

local function buildBoards()
	local folder = Instance.new("Folder")
	folder.Name = "Leaderboards"
	for _, board in BOARDS do
		local part = Instance.new("Part")
		part.Name = board
		part.Anchored = true
		part.Size = Vector3.new(8, 10, 0.4)
		part.Color = Color3.fromRGB(120, 20, 20)
		part.Material = Enum.Material.Wood
		local position = POSITIONS[board] + Vector3.new(0, 5, 0)
		part.CFrame = CFrame.lookAt(position, Vector3.new(0, 5, 0))
		part:SetAttribute("BoardId", board)
		part.Parent = folder
	end
	folder.Parent = Workspace
end

function LeaderboardService.Init()
	buildBoards()
end

function LeaderboardService.Start()
	Players.PlayerAdded:Connect(function(player)
		Remotes.Event("Leaderboards"):FireClient(player, latest)
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_SECONDS)
		end
	end)
end

return LeaderboardService
