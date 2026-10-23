--!strict
-- Client entry point: Init/Start every controller in ./Controllers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game"))
local Loader = require(Shared:WaitForChild("Util"):WaitForChild("Loader"))

Loader.load(script.Parent:FindFirstChild("Controllers"))
print(`[{Game.Name}] Client: Services started`)
