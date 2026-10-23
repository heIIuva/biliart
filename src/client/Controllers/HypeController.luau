--!strict
-- Hype presentation (GDD 7.4): slow motion and a camera push-in around the decisive moment of a
-- titled shot, then the splash (huge hanzi, name, rarity, combo), camera shake and the title sound.
-- Splashes read without sound: big high-contrast text. Also shows rare-title announcements.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Hype = require(Shared.Config.Hype)
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local Remotes = require(Shared.Net.Remotes)
local ShotClassifier = require(Shared.Pool.ShotClassifier)
local TableSpace = require(Shared.World.TableSpace)
local Text = require(Shared.Util.Text)
local Titles = require(Shared.Config.Titles)
local Sfx = require(script.Parent.Parent.Util.Sfx)
local TableViewController = require(script.Parent.TableViewController)

local Kind = PoolPhysics.EventKind
local GOLD = Color3.fromRGB(255, 205, 60)
local GREY = Color3.fromRGB(170, 170, 170)
local DARK = Color3.fromRGB(20, 10, 6)
local PUSH_IN = 0.55 -- camera distance share during the slow-motion push-in

type Moment = { t: number, x: number?, y: number? }

local moments: { [any]: Moment } = setmetatable({}, { __mode = "k" }) :: any -- by playback table
local splash: ScreenGui
local hanziLabel: TextLabel
local nameLabel: TextLabel
local rarityLabel: TextLabel
local comboLabel: TextLabel
local splashScale: UIScale
local banner: TextLabel
local shakeUntil, shakeStrength = 0, 0
local shakeBase: CFrame? = nil -- camera rest position while shaking
local baseCamera: CFrame? = nil

-- The decisive event: the last pot / rattle / flight off the table, else the end of the shot.
local function findMoment(view: TableViewController.View, events: { PoolPhysics.Event }, duration: number): Moment
	local moment: Moment = { t = duration }
	for _, e in events do
		if e.kind == Kind.Pocketed or e.kind == Kind.Rattle then
			local pocket = view.geometry.pockets[e.b]
			moment = { t = e.t, x = if pocket then pocket.x else nil, y = if pocket then pocket.y else nil }
		elseif e.kind == Kind.OffTable then
			moment = { t = e.t }
		end
	end
	return moment
end

local function label(name: string, parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = size
	l.Position = position
	l.Font = Enum.Font.GothamBlack
	l.TextSize = textSize
	l.TextColor3 = GOLD
	l.TextStrokeColor3 = DARK
	l.TextStrokeTransparency = 0
	l.Text = ""
	l.Parent = parent
	return l
end

local function buildGui()
	splash = Instance.new("ScreenGui")
	splash.Name = "HypeSplash"
	splash.ResetOnSpawn = false
	splash.Enabled = false
	splash.DisplayOrder = 10
	splash.IgnoreGuiInset = true
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = splash
	splashScale = Instance.new("UIScale")
	splashScale.Parent = root
	hanziLabel = label("Hanzi", root, UDim2.fromScale(1, 0.3), UDim2.fromScale(0.5, 0.38), 110)
	nameLabel = label("Name", root, UDim2.fromScale(1, 0.1), UDim2.fromScale(0.5, 0.56), 48)
	rarityLabel = label("Rarity", root, UDim2.fromScale(1, 0.06), UDim2.fromScale(0.5, 0.65), 24)
	rarityLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	comboLabel = label("Combo", root, UDim2.fromScale(1, 0.06), UDim2.fromScale(0.5, 0.22), 30)
	splash.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local announce = Instance.new("ScreenGui")
	announce.Name = "HypeAnnouncement"
	announce.ResetOnSpawn = false
	announce.DisplayOrder = 9
	banner = Instance.new("TextLabel")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 104)
	banner.Size = UDim2.fromOffset(620, 40)
	banner.BackgroundColor3 = DARK
	banner.BackgroundTransparency = 0.25
	banner.Font = Enum.Font.GothamBold
	banner.TextSize = 20
	banner.TextColor3 = GOLD
	banner.Visible = false
	banner.Parent = announce
	announce.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function showSplash(hype: Remotes.HypePayload)
	local title = ShotClassifier.byId(hype.titleId)
	if not title then
		return
	end
	local isAnti = title.kind == "Anti"
	local color = if isAnti then GREY else GOLD
	hanziLabel.Text = title.hanzi
	hanziLabel.TextColor3 = color
	nameLabel.Text = Text.get(title.nameKey)
	nameLabel.TextColor3 = color
	rarityLabel.Text = if hype.rarity
		then Text.format("HYPE_RARITY", { percent = string.format("%.1f", hype.rarity) })
		else ""
	comboLabel.Text = if hype.combo > 1 then Text.format("HYPE_COMBO", { combo = hype.combo }) else ""

	local comboScale = 1 + Hype.ComboScalePerLevel * (hype.combo - 1)
	splash.Enabled = true
	splashScale.Scale = 0.2
	TweenService:Create(splashScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = comboScale,
	}):Play()
	shakeStrength = title.cameraShake * comboScale
	shakeUntil = os.clock() + 0.5
	Sfx.play(title.sound, math.min(1, 0.7 * comboScale))
	Sfx.play(title.announcer, 1)
	task.delay(Hype.SplashSeconds, function()
		splash.Enabled = false
	end)
end

local function showBanner(message: Remotes.Announcement)
	local title = ShotClassifier.byId(message.titleId)
	if not title then
		return
	end
	banner.Text = Text.format("HYPE_ANNOUNCE", {
		player = message.playerName,
		title = `{title.hanzi} {Text.get(title.nameKey)}`,
	})
	banner.Visible = true
	task.delay(3, function()
		banner.Visible = false
	end)
end

local function update()
	local camera = Workspace.CurrentCamera
	local view = TableViewController.seatedView()
	local playback = view and view.playback
	local pushed = false
	if view and playback and playback.hype then
		local title = ShotClassifier.byId(playback.hype.titleId) :: Titles.Title?
		local moment = moments[playback]
		if not moment then
			moment = findMoment(view, playback.events, playback.duration)
			moments[playback] = moment
		end
		local inWindow = playback.t >= moment.t - Hype.SlowMoLead and playback.t <= moment.t + Hype.SlowMoTail
		playback.timeScale = if title and title.slowMo and inWindow then Hype.SlowMoScale else 1
		if inWindow and title and title.slowMo and moment.x and moment.y then
			pushed = true
			baseCamera = baseCamera or camera.CFrame
			local base = baseCamera :: CFrame
			local target = TableSpace.toWorld(view.surface, moment.x, moment.y, 0)
			local distance = (base.Position - view.surface.Position).Magnitude * PUSH_IN
			local goal = CFrame.lookAt(target + view.surface.UpVector * distance, target, base.UpVector)
			camera.CFrame = camera.CFrame:Lerp(goal, 0.12)
		end
	end
	if not pushed and baseCamera then
		camera.CFrame = camera.CFrame:Lerp(baseCamera, 0.15)
		if (camera.CFrame.Position - baseCamera.Position).Magnitude < 0.05 then
			camera.CFrame = baseCamera
			baseCamera = nil
		end
	end
	if os.clock() < shakeUntil and view then
		shakeBase = shakeBase or camera.CFrame
		local amount = shakeStrength * 0.15
		camera.CFrame = (shakeBase :: CFrame)
			* CFrame.new((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, 0)
	elseif shakeBase then
		camera.CFrame = shakeBase
		shakeBase = nil
	end
end

local HypeController = {}

function HypeController.Init()
	buildGui()
end

function HypeController.Start()
	TableViewController.PlaybackFinished:Connect(function(tableId, hype)
		local view = TableViewController.seatedView()
		if hype and view and view.id == tableId then
			showSplash(hype)
		end
	end)
	Remotes.Event("Announcement").OnClientEvent:Connect(showBanner)
	RunService.RenderStepped:Connect(update)
end

return HypeController
