--!strict
-- Tables in the world and seating (one player per table). Holds each table's balls;
-- matches on a table are run by MatchService.

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
	seat: CFrame,
	balls: { PoolPhysics.BallState },
	prompt: ProximityPrompt,
	occupant: Player?,
}

local tables: { [string]: Entry } = {}
local seated: { [Player]: Entry } = {}
local actionLimiter = RateLimiter.new(2, 4)
local random = Random.new()

local TableService = {
	Seated = Signal.new(), -- (player, entry)
	Unseated = Signal.new(), -- (player, entry): left, died or disconnected
}

local function snapshot(entry: Entry): Remotes.TableSnapshot
	return { tableId = entry.id, variant = entry.variant, surface = entry.surface, balls = entry.balls }
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function seat(player: Player, entry: Entry)
	local root = rootOf(player)
	if seated[player] or entry.occupant or not root then
		return
	end
	seated[player] = entry
	entry.occupant = player
	entry.prompt.Enabled = false
	root.Anchored = true
	root.CFrame = entry.seat
	Remotes.Event("SeatChanged"):FireClient(player, entry.id)
	TableService.Seated:Fire(player, entry)
end

local function unseat(player: Player)
	local entry = seated[player]
	if not entry then
		return
	end
	seated[player] = nil
	entry.occupant = nil
	entry.prompt.Enabled = true
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	if player.Parent then
		Remotes.Event("SeatChanged"):FireClient(player, nil)
	end
	TableService.Unseated:Fire(player, entry)
end

function TableService.get(tableId: string): Entry?
	return tables[tableId]
end

function TableService.tableOf(player: Player): Entry?
	return seated[player]
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
		local built = TableBuilder.build(placement.id, variant, CFrame.new(placement.x, 0, placement.z))
		local prompt = built.model:FindFirstChild("PlayPrompt", true) :: ProximityPrompt
		local geometry = TableGeometry.get(variant)
		local entry: Entry = {
			id = placement.id,
			variant = variant,
			geometry = geometry,
			surface = built.surface,
			seat = built.seat,
			balls = Rack.eightBall(geometry, random:NextInteger(1, 2147483646)),
			prompt = prompt,
			occupant = nil,
		}
		tables[entry.id] = entry
		prompt.Triggered:Connect(function(player)
			seat(player, entry)
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
