--!strict
-- Tables in the world and seating: two seats per table (head and foot end). Holds each table's
-- balls; matches are run by MatchService. The prompt of the King table only queues (KingTableService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local Rack = require(Shared.Pool.Rack)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)
local TableGeometry = require(Shared.Pool.TableGeometry)
local Tables = require(Shared.Config.Tables)
local TableBuilder = require(script.Parent.Parent.World.TableBuilder)

export type Entry = {
	id: string,
	variant: TableGeometry.Variant,
	geometry: TableGeometry.Geometry,
	surface: CFrame,
	seats: { CFrame },
	balls: { PoolPhysics.BallState },
	prompt: ProximityPrompt,
	occupants: { [number]: Player }, -- by seat index
	model: Model,
}

local tables: { [string]: Entry } = {}
local seated: { [Player]: { entry: Entry, index: number } } = {}
local actionLimiter = RateLimiter.new(2, 4)
local random = Random.new()

local TableService = {
	Seated = Signal.new(), -- (player, entry, index)
	Unseated = Signal.new(), -- (player, entry, index): left, died or disconnected
	KingPrompt = Signal.new(), -- (player): someone wants to play at the King table
}

local function snapshot(entry: Entry): Remotes.TableSnapshot
	return { tableId = entry.id, variant = entry.variant, surface = entry.surface, balls = entry.balls }
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function unseat(player: Player)
	local place = seated[player]
	if not place then
		return
	end
	seated[player] = nil
	place.entry.occupants[place.index] = nil
	place.entry.prompt.Enabled = not place.entry.occupants[1] or place.entry.id == Tables.KingTableId
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	if player.Parent then
		Remotes.Event("SeatChanged"):FireClient(player, nil)
	end
	TableService.Unseated:Fire(player, place.entry, place.index)
end

-- Seats the player at a free seat (leaving any other seat first); true on success.
function TableService.seatAt(player: Player, entry: Entry, index: number): boolean
	local root = rootOf(player)
	local current = seated[player]
	if current and current.entry == entry and current.index == index then
		return true
	end
	if entry.occupants[index] or not root then
		return false
	end
	unseat(player)
	seated[player] = { entry = entry, index = index }
	entry.occupants[index] = player
	entry.prompt.Enabled = entry.id == Tables.KingTableId
	root.Anchored = true
	root.CFrame = entry.seats[index]
	Remotes.Event("SeatChanged"):FireClient(player, entry.id)
	TableService.Seated:Fire(player, entry, index)
	return true
end

function TableService.unseat(player: Player)
	unseat(player)
end

function TableService.get(tableId: string): Entry?
	return tables[tableId]
end

-- The player's table and seat index, if seated.
function TableService.tableOf(player: Player): (Entry?, number)
	local place = seated[player]
	if place then
		return place.entry, place.index
	end
	return nil, 0
end

-- Replaces the table's balls; `broadcast` sends a TableState so clients redraw them.
function TableService.setBalls(entry: Entry, balls: { PoolPhysics.BallState }, broadcast: boolean)
	entry.balls = balls
	if broadcast then
		Remotes.Event("TableState"):FireAllClients(snapshot(entry))
	end
end

function TableService.rack(entry: Entry)
	TableService.setBalls(entry, Rack.eightBall(entry.geometry, random:NextInteger(1, 2147483646)), true)
end

function TableService.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Tables"
	for _, placement in Tables.Placements do
		local variant: TableGeometry.Variant = placement.variant :: any
		local built = TableBuilder.build(placement.id, variant, CFrame.new(placement.x, 0, placement.z), placement.king)
		local prompt = built.model:FindFirstChild("PlayPrompt", true) :: ProximityPrompt
		local geometry = TableGeometry.get(variant)
		local entry: Entry = {
			id = placement.id,
			variant = variant,
			geometry = geometry,
			surface = built.surface,
			seats = built.seats,
			balls = Rack.eightBall(geometry, random:NextInteger(1, 2147483646)),
			prompt = prompt,
			occupants = {},
			model = built.model,
		}
		tables[entry.id] = entry
		prompt.Triggered:Connect(function(player)
			if entry.id == Tables.KingTableId then
				TableService.KingPrompt:Fire(player)
			else
				TableService.seatAt(player, entry, 1)
			end
		end)
		built.model.Parent = folder
	end
	folder.Parent = Workspace
end

function TableService.Start()
	Remotes.Event("LeaveTable").OnServerEvent:Connect(function(player)
		if actionLimiter:Allow(player) then
			unseat(player)
		end
	end)
	local function onPlayerAdded(player: Player)
		for _, entry in tables do
			Remotes.Event("TableState"):FireClient(player, snapshot(entry))
		end
		player.CharacterRemoving:Connect(function()
			unseat(player)
		end)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		unseat(player)
		actionLimiter:Forget(player)
	end)
end

return TableService
