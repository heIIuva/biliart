--!strict
-- King of the table (GDD 12): the Tiger table in the middle of the lobby. Players queue at its
-- prompt; the winner stays as king (a crown over the head) and earns a fixed reward for every
-- defense; the loser leaves the table and the next challenger sits down. Spectators follow the
-- match on the table itself and on the big screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Social = require(Shared.Config.Social)
local Tables = require(Shared.Config.Tables)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local TableService = require(script.Parent.TableService)

local queue: { Player } = {}
local king: Player? = nil
local scheduled = false

local KingTableService = {}

function KingTableService.isKing(player: Player): boolean
	return king == player
end

local function setCrown(player: Player?, on: boolean)
	local head = player and player.Character and player.Character:FindFirstChild("Head")
	if not head then
		return
	end
	local crown = head:FindFirstChild("KingCrown")
	if on and not crown then
		local gui = Instance.new("BillboardGui")
		gui.Name = "KingCrown"
		gui.Size = UDim2.fromOffset(60, 60)
		gui.StudsOffset = Vector3.new(0, 2.5, 0)
		gui.AlwaysOnTop = true
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Text = "👑"
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = head
	elseif not on and crown then
		crown:Destroy()
	end
end

local function sendQueue()
	for i, player in queue do
		DataService.notify(player, "KING_QUEUE", { position = i })
	end
end

-- Starts the next match if the table is free and there are two contenders.
local function advance()
	scheduled = false
	local entry = TableService.get(Tables.KingTableId)
	if not entry or MatchService.isPlaying(entry) then
		return
	end
	if king and king.Parent ~= Players then
		king = nil
	end
	if not king and #queue > 0 then
		king = table.remove(queue, 1)
	end
	local challenger = table.remove(queue, 1)
	local current = king
	if not current or not challenger then
		if challenger then
			table.insert(queue, 1, challenger)
		end
		if current then
			TableService.seatAt(current, entry, 1)
			setCrown(current, true)
		end
		sendQueue()
		return
	end
	TableService.seatAt(current, entry, 1)
	if not TableService.seatAt(challenger, entry, 2) then
		return
	end
	setCrown(current, true)
	sendQueue()
	MatchService.startPvp(entry, current, challenger, "King")
end

local function schedule(delaySeconds: number)
	if not scheduled then
		scheduled = true
		task.delay(delaySeconds, advance)
	end
end

-- Spectator screen behind the King table; clients draw the match on it.
function KingTableService.Init()
	local spot = Tables.BigScreen
	local screen = Instance.new("Part")
	screen.Name = "KingScreen"
	screen.Anchored = true
	screen.Size = Vector3.new(28, 16, 0.5)
	screen.Color = Color3.fromRGB(15, 10, 8)
	local position = Vector3.new(spot.x, spot.y, spot.z)
	screen.CFrame = CFrame.lookAt(position, Vector3.new(spot.x, spot.y, spot.z + 10))
	screen:SetAttribute("ScreenFor", Tables.KingTableId)
	screen.Parent = workspace
end

function KingTableService.Start()
	TableService.KingPrompt:Connect(function(player)
		if player == king or table.find(queue, player) then
			return
		end
		table.insert(queue, player)
		sendQueue()
		schedule(0)
	end)
	MatchService.Finished:Connect(function(entry, mode, winner, loser)
		if mode ~= "King" or entry.id ~= Tables.KingTableId then
			return
		end
		if winner and winner == king then
			DataService.addCurrency(winner, "coins", Social.KingDefenseCoins, "Gameplay", "KingDefense")
			DataService.notify(winner, "KING_DEFENDED", { amount = Social.KingDefenseCoins })
		elseif winner then
			setCrown(king, false)
			king = winner
			DataService.notify(winner, "KING_NEW")
		end
		if loser then
			setCrown(loser, false)
			task.delay(Social.KingNextMatchDelay - 1, function()
				TableService.unseat(loser)
			end)
		end
		schedule(Social.KingNextMatchDelay)
	end)
	-- The king standing up gives up the crown.
	TableService.Unseated:Connect(function(player, entry)
		if entry.id == Tables.KingTableId and player == king and not MatchService.isPlaying(entry) then
			setCrown(king, false)
			king = nil
			schedule(1)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
		end
		if king == player then
			king = nil
			schedule(1)
		end
	end)
end

return KingTableService
