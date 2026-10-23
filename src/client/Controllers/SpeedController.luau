--!strict
-- Speed pool on the client: live frames arrive ~20 times a second (unreliable); balls are drawn
-- 100 ms in the past, interpolated between the two frames around that time. Also tells the aim
-- code which cue ball is mine and whether it rests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local Remotes = require(Shared.Net.Remotes)
local Speed = require(Shared.Config.Speed)
local TableSpace = require(Shared.World.TableSpace)
local TrajectoryCodec = require(Shared.Pool.TrajectoryCodec)
local TableViewController = require(script.Parent.TableViewController)

local STRIDE = PoolPhysics.FRAME_STRIDE
local DELAY = 0.1
local REST_EPSILON = 1e-4

type Sample = { t: number, positions: { [number]: { number } } } -- id -> { x, y, z, qx, qy, qz, qw }

local samples: { [string]: { Sample } } = {}
local clockOffset: { [string]: number } = {} -- world time minus os.clock()
local myCue = 0

local SpeedController = {}

function SpeedController.setMyCue(id: number)
	myCue = id
end

function SpeedController.myCueId(): number
	return myCue
end

-- True if my cue ball did not move between the last two frames of this table.
function SpeedController.myCueResting(tableId: string): boolean
	local list = samples[tableId]
	if not list or #list < 2 then
		return true
	end
	local a, b = list[#list - 1].positions[myCue], list[#list].positions[myCue]
	return a ~= nil and b ~= nil and math.abs(a[1] - b[1]) < REST_EPSILON and math.abs(a[2] - b[2]) < REST_EPSILON
end

local function onFrame(tableId: string, packet: buffer)
	local frame = TrajectoryCodec.decodeFrame(packet)
	local positions: { [number]: { number } } = {}
	local data = frame.data
	for i = 1, #data, STRIDE do
		positions[data[i]] =
			{ data[i + 1], data[i + 2], data[i + 3], data[i + 4], data[i + 5], data[i + 6], data[i + 7] }
	end
	local list = samples[tableId] or {}
	samples[tableId] = list
	table.insert(list, { t = frame.t, positions = positions })
	while #list > 8 do
		table.remove(list, 1)
	end
	clockOffset[tableId] = math.max(clockOffset[tableId] or -math.huge, frame.t - os.clock())

	-- Keep the view's resting state in sync for aiming (latest frame).
	local view = TableViewController.view(tableId)
	if view then
		local balls: { PoolPhysics.BallState } = {}
		for id, p in positions do
			table.insert(
				balls,
				{ id = id, x = p[1], y = p[2], status = "Stationary", qx = p[4], qy = p[5], qz = p[6], qw = p[7] }
			)
		end
		for _, id in { 0, Speed.SecondCueId, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 } do
			if not positions[id] then
				table.insert(balls, { id = id, x = 0, y = 0, status = "Pocketed" })
			end
		end
		if not view.parts[Speed.SecondCueId] then
			TableViewController.ensureBalls(view, balls)
		else
			view.balls = balls
		end
		for id, part in view.parts do
			part.Parent = if positions[id] then view.folder else nil
		end
	end
end

local function render()
	for tableId, list in samples do
		local view = TableViewController.view(tableId)
		local offset = clockOffset[tableId]
		if not view or not offset or #list < 2 then
			continue
		end
		local t = os.clock() + offset - DELAY
		local older, newer = list[1], list[#list]
		for i = #list - 1, 1, -1 do
			if list[i].t <= t then
				older, newer = list[i], list[i + 1]
				break
			end
		end
		local span = newer.t - older.t
		local alpha = if span > 0 then math.clamp((t - older.t) / span, 0, 1) else 1
		for id, part in view.parts do
			local a, b = older.positions[id], newer.positions[id]
			if a and b then
				local from = TableSpace.ballCFrame(view.surface, a[1], a[2], a[3], a[4], a[5], a[6], a[7])
				local to = TableSpace.ballCFrame(view.surface, b[1], b[2], b[3], b[4], b[5], b[6], b[7])
				part.CFrame = from:Lerp(to, alpha)
			end
		end
	end
end

function SpeedController.Start()
	Remotes.Unreliable("SpeedState").OnClientEvent:Connect(onFrame)
	Remotes.Event("SpeedEvents").OnClientEvent:Connect(function(tableId: string, events: { PoolPhysics.Event })
		local view = TableViewController.view(tableId)
		if view then
			TableViewController.playEvents(view, events)
		end
	end)
	Remotes.Event("MatchState").OnClientEvent:Connect(function(snapshot: Remotes.MatchSnapshot)
		if snapshot.mode ~= "Speed" or snapshot.phase ~= "Playing" then
			samples[snapshot.tableId] = nil
			clockOffset[snapshot.tableId] = nil
		end
	end)
	RunService.RenderStepped:Connect(render)
end

return SpeedController
