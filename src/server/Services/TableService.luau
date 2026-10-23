--!strict
-- Tables in the world and seating.
-- Phase 2 test mode "free play": no rules. Anyone seated may shoot while the table is idle;
-- the server simulates and every client replays the trajectory. Matches replace this in phase 3.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local Rack = require(Shared.Pool.Rack)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local TableGeometry = require(Shared.Pool.TableGeometry)
local Tables = require(Shared.Config.Tables)
local TrajectoryCodec = require(Shared.Pool.TrajectoryCodec)
local Validate = require(Shared.Util.Validate)
local TableBuilder = require(script.Parent.Parent.World.TableBuilder)

local PLAYBACK_GRACE = 0.5 -- seconds after a trajectory ends before the table takes the next shot

type TableEntry = {
	id: string,
	variant: TableGeometry.Variant,
	geometry: TableGeometry.Geometry,
	surface: CFrame,
	seat: CFrame,
	balls: { PoolPhysics.BallState },
	busyUntil: number,
}

local tables: { [string]: TableEntry } = {}
local seated: { [Player]: string } = {}
local shotLimiter = RateLimiter.new(1, 2)
local actionLimiter = RateLimiter.new(2, 4)
local random = Random.new()

local function snapshot(entry: TableEntry): Remotes.TableSnapshot
	return { tableId = entry.id, variant = entry.variant, surface = entry.surface, balls = entry.balls }
end

local function rack(entry: TableEntry)
	entry.balls = Rack.eightBall(entry.geometry, random:NextInteger(1, 2147483646))
end

-- Puts a scratched cue ball back near the head spot, on the first free place.
local function respot(geometry: TableGeometry.Geometry, balls: { PoolPhysics.BallState }, cue: PoolPhysics.BallState)
	local R = geometry.ballRadius
	for i = 0, 59 do
		local x = geometry.headSpotX - (i % 10) * 2.2 * R
		local row = i // 10
		local y = (row + 1) // 2 * 2.2 * R * (if row % 2 == 0 then 1 else -1)
		local free = true
		for _, b in balls do
			if b ~= cue and b.status == "Stationary" and (b.x - x) ^ 2 + (b.y - y) ^ 2 < (2 * R + 1e-4) ^ 2 then
				free = false
				break
			end
		end
		if free then
			cue.x, cue.y, cue.status = x, y, "Stationary"
			return
		end
	end
end

-- Free play: respot a scratched cue ball, re-rack once every object ball is gone.
local function settle(entry: TableEntry, balls: { PoolPhysics.BallState })
	local remaining = 0
	for _, b in balls do
		if b.id ~= 0 and b.status == "Stationary" then
			remaining += 1
		end
	end
	if remaining == 0 then
		rack(entry)
		return
	end
	for _, b in balls do
		if b.id == 0 and b.status ~= "Stationary" then
			respot(entry.geometry, balls, b)
		end
	end
	entry.balls = balls
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function seat(player: Player, entry: TableEntry)
	local root = rootOf(player)
	if seated[player] or not root then
		return
	end
	seated[player] = entry.id
	root.Anchored = true
	root.CFrame = entry.seat
	Remotes.Event("SeatChanged"):FireClient(player, entry.id)
end

local function unseat(player: Player)
	if not seated[player] then
		return
	end
	seated[player] = nil
	local root = rootOf(player)
	if root then
		root.Anchored = false
	end
	Remotes.Event("SeatChanged"):FireClient(player, nil)
end

local function onShot(player: Player, payload: unknown)
	if not shotLimiter:Allow(player) then
		return
	end
	local entry = tables[seated[player] or ""]
	local shot = Validate.shotParams(payload)
	if not entry or not shot or os.clock() < entry.busyUntil then
		return
	end
	local result = PoolPhysics.simulateShot({ geometry = entry.geometry, balls = entry.balls }, shot)
	settle(entry, result.finalState)
	entry.busyUntil = os.clock() + result.duration + PLAYBACK_GRACE
	local message: Remotes.ShotResultPayload = {
		tableId = entry.id,
		trajectory = TrajectoryCodec.encode(result),
		balls = entry.balls,
	}
	-- ponytail: every client gets every table's shots; limit to nearby players when tables multiply (phase 7).
	Remotes.Event("ShotResult"):FireAllClients(message)
end

local function onRerack(player: Player)
	local entry = tables[seated[player] or ""]
	if not actionLimiter:Allow(player) or not entry or os.clock() < entry.busyUntil then
		return
	end
	rack(entry)
	Remotes.Event("TableState"):FireAllClients(snapshot(entry))
end

local function onPlayerAdded(player: Player)
	for _, entry in tables do
		Remotes.Event("TableState"):FireClient(player, snapshot(entry))
	end
	player.CharacterRemoving:Connect(function()
		unseat(player)
	end)
end

local TableService = {}

function TableService.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Tables"
	for _, placement in Tables.FreePlay do
		local variant: TableGeometry.Variant = placement.variant :: any
		local built = TableBuilder.build(placement.id, variant, CFrame.new(placement.x, 0, placement.z))
		local entry: TableEntry = {
			id = placement.id,
			variant = variant,
			geometry = TableGeometry.get(variant),
			surface = built.surface,
			seat = built.seat,
			balls = {},
			busyUntil = 0,
		}
		rack(entry)
		tables[entry.id] = entry
		local prompt = built.model:FindFirstChild("PlayPrompt", true) :: ProximityPrompt
		prompt.Triggered:Connect(function(player)
			seat(player, entry)
		end)
		built.model.Parent = folder
	end
	folder.Parent = Workspace
end

function TableService.Start()
	Remotes.Event("Shot").OnServerEvent:Connect(onShot)
	Remotes.Event("Rerack").OnServerEvent:Connect(onRerack)
	Remotes.Event("LeaveTable").OnServerEvent:Connect(function(player)
		if actionLimiter:Allow(player) then
			unseat(player)
		end
	end)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		seated[player] = nil
		shotLimiter:Forget(player)
		actionLimiter:Forget(player)
	end)
end

return TableService
