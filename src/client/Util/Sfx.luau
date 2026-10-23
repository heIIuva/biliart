--!strict
-- Plays sounds by Config.Assets key. ID 0 = placeholder: prints a stub line instead of playing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("Config"):WaitForChild("Assets"))
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game"))

local sounds: { [string]: Sound } = {}

local Sfx = {}

function Sfx.play(key: string, volume: number)
	local id = Assets.Sounds[key]
	if not id or id == 0 then
		if Game.LogSoundStubs then
			print(string.format("[sfx stub] %s %.2f", key, volume))
		end
		return
	end
	local sound = sounds[key]
	if not sound then
		local created = Instance.new("Sound")
		created.SoundId = `rbxassetid://{id}`
		created.Parent = SoundService
		sounds[key] = created
		sound = created
	end
	sound.Volume = volume
	SoundService:PlayLocalSound(sound)
end

return Sfx
