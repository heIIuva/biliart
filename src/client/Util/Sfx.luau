--!strict
-- Plays sounds by Config.Assets key. ID 0 = placeholder: prints a stub line instead of playing.
-- Each play is its own short-lived Sound (hits overlap on a break) limited to the asset's region.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("Config"):WaitForChild("Assets"))
local Game = require(Shared:WaitForChild("Config"):WaitForChild("Game"))

local MIN_INTERVAL = 0.03 -- the same sound at most once per 30 ms, or a break turns into noise

local templates: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}

local Sfx = {}

function Sfx.play(key: string, volume: number)
	local asset = Assets.Sounds[key]
	if not asset or asset.id == 0 then
		if Game.LogSoundStubs then
			print(string.format("[sfx stub] %s %.2f", key, volume))
		end
		return
	end
	local now = os.clock()
	if now - (lastPlayed[key] or 0) < MIN_INTERVAL then
		return
	end
	lastPlayed[key] = now

	local template = templates[key]
	if not template then
		local created = Instance.new("Sound")
		created.SoundId = `rbxassetid://{asset.id}`
		created.PlaybackRegionsEnabled = true
		created.PlaybackRegion = NumberRange.new(asset.start, asset.start + asset.length)
		templates[key] = created
		template = created
	end
	local sound = template:Clone()
	sound.Volume = math.min(asset.gain * volume, 10)
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, asset.length + 0.5)
end

return Sfx
