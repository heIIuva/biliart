--!strict
-- Single source of truth for every RemoteEvent / RemoteFunction and their payload types.
-- Server calls Remotes.Setup() once at startup; both sides fetch remotes by name.
-- Every server handler must validate types/ranges and go through a RateLimiter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PoolPhysics = require("../Pool/PoolPhysics")

-- Client -> server: cue strike intent. Server re-validates everything.
export type ShotParams = {
	angle: number, -- radians
	power: number, -- 0..1
	spinX: number, -- tip offset on the cue ball, unit circle
	spinY: number,
	elevation: number, -- radians, 0..Config.Physics.MaxElevation
	calledPocket: number?, -- required when shooting the 8-ball
	cueBallPos: { x: number, y: number }?, -- ball in hand only
}

-- Server -> clients: everything needed to draw a table.
export type TableSnapshot = {
	tableId: string,
	variant: string, -- TableGeometry.Variant
	surface: CFrame, -- center of the cloth surface, see World/TableSpace
	balls: { PoolPhysics.BallState },
}

-- The title a shot earned, for the splash.
export type HypePayload = {
	titleId: string,
	combo: number, -- titles in a row this visit (1 = first)
	rarity: number?, -- percent of all shots, nil while there is too little data
	playerName: string,
}

-- Server -> clients after a shot: play `trajectory` (TrajectoryCodec), then snap to `balls`.
export type ShotResultPayload = {
	tableId: string,
	trajectory: buffer,
	balls: { PoolPhysics.BallState },
	hype: HypePayload?,
}

-- Server -> clients: a rare title somewhere on this server (or another one).
export type Announcement = {
	playerName: string,
	titleId: string,
	crossServer: boolean,
}

export type MatchPlayer = {
	name: string, -- player display name, or a localization key for bots
	userId: number, -- 0 for bots
	isBot: boolean,
	group: string?, -- "Solids" | "Stripes", nil while the table is open
}

-- Server -> clients: the match at a table. Sent at the start of every turn (after the previous
-- shot has played back) and when the match starts or ends.
export type MatchSnapshot = {
	tableId: string,
	phase: "Idle" | "Playing" | "Over",
	players: { MatchPlayer },
	current: number, -- index into players
	isBreak: boolean,
	ballInHand: boolean,
	kitchenOnly: boolean, -- ball in hand behind the head string (break)
	mustCall: boolean, -- the shooter must call a pocket (shooting the 8)
	turnEndsAt: number, -- workspace:GetServerTimeNow() when the turn times out
	reasonKey: string?, -- outcome of the previous shot (localization key)
	winner: number?,
}

local DEFINITIONS: { [string]: "RemoteEvent" | "RemoteFunction" } = {
	Shot = "RemoteEvent", -- client -> server: ShotParams (+ calledPocket, cueBallPos); shooter's turn only
	ShotResult = "RemoteEvent", -- server -> clients: ShotResultPayload
	TableState = "RemoteEvent", -- server -> clients: TableSnapshot (on join, on a new rack)
	MatchState = "RemoteEvent", -- server -> clients: MatchSnapshot
	SeatChanged = "RemoteEvent", -- server -> client: tableId or nil
	LeaveTable = "RemoteEvent", -- client -> server: no payload
	StartMatch = "RemoteEvent", -- client -> server: bot level "Easy" | "Medium" | "Hard"
	StartTutorial = "RemoteEvent", -- client -> server: no payload
	Announcement = "RemoteEvent", -- server -> clients: Announcement
	Debug = "RemoteEvent", -- client -> server, Studio only: { action = "title", id = titleId }
	ClipOpened = "RemoteEvent", -- client -> server: analytics only
	ClipScreenshot = "RemoteEvent", -- client -> server: analytics only
}

local FOLDER_NAME = "Remotes"

local Remotes = {}

function Remotes.Setup()
	assert(RunService:IsServer(), "Remotes.Setup is server-only")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for name, className in DEFINITIONS do
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function get(name: string): Instance
	assert(DEFINITIONS[name], `Unknown remote "{name}"`)
	return ReplicatedStorage:WaitForChild(FOLDER_NAME):WaitForChild(name)
end

function Remotes.Event(name: string): RemoteEvent
	return get(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return get(name) :: RemoteFunction
end

return Remotes
