--!strict
-- Single source of truth for every RemoteEvent / RemoteFunction and their payload types.
-- Server calls Remotes.Setup() once at startup; both sides fetch remotes by name.
-- Every server handler must validate types/ranges and go through a RateLimiter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

local DEFINITIONS: { [string]: "RemoteEvent" | "RemoteFunction" } = {
	Shot = "RemoteEvent", -- client -> server: ShotParams
	ShotResult = "RemoteEvent", -- server -> clients: encoded trajectory + rules result (payload type in phase 2)
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
