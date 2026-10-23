--!strict
-- Draws the lobby leaderboard boards (parts placed by LeaderboardService) with localized titles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Text = require(Shared.Util.Text)
local Titles = require(Shared.Config.Titles)
local Kit = require(script.Parent.Parent.UI.Kit)

local TITLE_KEYS = {
	Wins = "BOARD_WINS",
	ShotOfDay = "BOARD_SHOT_OF_DAY",
	Dojo = "BOARD_DOJO",
	Rating = "BOARD_RATING",
	Trick = "BOARD_TRICK",
}

local latest: { [string]: { Remotes.LeaderboardRow } } = {}

-- Shot of the day stores a title priority: show the title instead of the number.
local function scoreText(board: string, score: number): string
	if board == "ShotOfDay" then
		for _, title in Titles do
			if title.priority == score then
				return title.hanzi .. " " .. Text.get(title.nameKey)
			end
		end
	end
	return tostring(score)
end

local function draw(part: BasePart)
	local board = part:GetAttribute("BoardId")
	if type(board) ~= "string" then
		return
	end
	local surface = part:FindFirstChild("Board") :: SurfaceGui?
	if not surface then
		local created = Instance.new("SurfaceGui")
		created.Name = "Board"
		created.Face = Enum.NormalId.Front
		created.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		created.PixelsPerStud = 40
		created.Adornee = part
		created.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		surface = created
	end
	local gui = surface :: SurfaceGui
	Kit.clear(gui)
	local list = Kit.frame("List", gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	Kit.label("Title", list, Text.get(TITLE_KEYS[board] or board), {
		Size = UDim2.new(1, 0, 0, 60),
		TextSize = 34,
		TextColor3 = Kit.GOLD,
		LayoutOrder = 0,
	})
	for _, row in (latest[board] or {}) :: { Remotes.LeaderboardRow } do
		Kit.label("Row", list, `{row.rank}. {row.name} — {scoreText(board, row.score)}`, {
			Size = UDim2.new(1, -20, 0, 30),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = row.rank,
		})
	end
end

local function drawAll()
	local folder = Workspace:FindFirstChild("Leaderboards")
	if folder then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") then
				draw(part)
			end
		end
	end
end

local LeaderboardController = {}

function LeaderboardController.Start()
	Remotes.Event("Leaderboards").OnClientEvent:Connect(function(boards)
		latest = boards
		drawAll()
	end)
	-- With streaming the boards can arrive later than the data.
	local function watch(folder: Instance)
		folder.ChildAdded:Connect(function(part)
			if part:IsA("BasePart") then
				draw(part)
			end
		end)
		drawAll()
	end
	local folder = Workspace:FindFirstChild("Leaderboards")
	if folder then
		watch(folder)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Leaderboards" then
			watch(child)
		end
	end)
end

return LeaderboardController
