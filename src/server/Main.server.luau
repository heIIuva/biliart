--!strict
-- Server entry point: create remotes, then Init/Start every service in ./Services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Loader = require(Shared.Util.Loader)
local Remotes = require(Shared.Net.Remotes)

Remotes.Setup()
Loader.load(script.Parent:FindFirstChild("Services"))
print(`[{Game.Name}] Server: Services started`)
