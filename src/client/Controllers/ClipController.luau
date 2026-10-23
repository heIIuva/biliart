--!strict
-- Clip mode (GDD 8): a vertical 9:16 replay of the last shot for reels. The table is turned with its
-- long side up, game UI is hidden, the title sits at the top and the game name at the bottom inside
-- the platforms' safe zones; buttons live outside the frame so they never end up in the crop.
-- The replay ends on a short close-up of the avatar. Also makes the avatar react after own titles.

local CaptureService = game:GetService("CaptureService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clip = require(Shared.Config.Clip)
local Game = require(Shared.Config.Game)
local Remotes = require(Shared.Net.Remotes)
local ShotClassifier = require(Shared.Pool.ShotClassifier)
local TableSpace = require(Shared.World.TableSpace)
local Text = require(Shared.Util.Text)
local TableViewController = require(script.Parent.TableViewController)

local GOLD = Color3.fromRGB(255, 205, 60)
local DARK = Color3.fromRGB(20, 10, 6)
local IVORY = Color3.fromRGB(245, 243, 230)
local TABLE_BORDER_METERS = 0.17

local player = Players.LocalPlayer
local offerUntil = 0
local offerHype = false
local active = false
local cinematic = false
local hiddenGuis: { ScreenGui } = {}
local clipGui: ScreenGui
local offerGui: ScreenGui
local offerButton: TextButton
local barLeft: Frame
local barRight: Frame
local frameOutline: Frame
local titleLabel: TextLabel
local watermark: TextLabel
local clipHype: Remotes.HypePayload? = nil

local function textLabel(name: string, parent: Instance, textSize: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Font = Enum.Font.GothamBlack
	l.TextSize = textSize
	l.TextColor3 = color
	l.TextStrokeColor3 = DARK
	l.TextStrokeTransparency = 0
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function sideButton(name: string, key: string, order: number, onActivated: () -> ())
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Size = UDim2.fromOffset(180, 50)
	b.Position = UDim2.new(0.5, 0, 0, 40 + order * 64)
	b.BackgroundColor3 = if order == 0 then Color3.fromRGB(190, 30, 30) else Color3.fromRGB(60, 60, 60)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 18
	b.TextColor3 = IVORY
	b.Text = Text.get(key)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = b
	b.Parent = barRight
	b.Activated:Connect(onActivated)
end

-- Camera that shows the table vertically inside the centered 9:16 frame, inside the safe zones.
local function verticalCamera(view: TableViewController.View): CFrame
	local g = view.geometry
	local length = TableSpace.studs(2 * (g.halfLength + TABLE_BORDER_METERS)) * (1 + Clip.TableMargin)
	local width = TableSpace.studs(2 * (g.halfWidth + TABLE_BORDER_METERS)) * (1 + Clip.TableMargin)
	local usableHeight = 1 - Clip.SafeTop - Clip.SafeBottom
	local usableWidth = Clip.Aspect * (1 - Clip.SafeRight)
	local tanHalf = math.tan(math.rad(Clip.CameraFov) / 2)
	local visibleHeight = math.max(length / usableHeight, width / usableWidth)
	local distance = visibleHeight / (2 * tanHalf)
	local up = view.surface.XVector -- long side goes up the screen
	local right = up:Cross(view.surface.UpVector)
	-- Center the table in the usable area: a bit up (bottom zone is bigger) and left (right zone).
	local shiftUp = (Clip.SafeBottom - Clip.SafeTop) / 2 * visibleHeight
	local shiftLeft = Clip.SafeRight / 2 * visibleHeight * Clip.Aspect
	local center = view.surface.Position - up * shiftUp + right * shiftLeft
	return CFrame.lookAt(center + view.surface.UpVector * distance, center, up)
end

local function layout()
	local viewport = Workspace.CurrentCamera.ViewportSize
	local frameHeight = viewport.Y
	local frameWidth = frameHeight * Clip.Aspect
	local side = math.max(0, (viewport.X - frameWidth) / 2)
	barLeft.Size = UDim2.fromOffset(side, viewport.Y)
	barRight.Size = UDim2.fromOffset(side, viewport.Y)
	barRight.Position = UDim2.fromOffset(side + frameWidth, 0)
	frameOutline.Position = UDim2.fromOffset(side, 0)
	frameOutline.Size = UDim2.fromOffset(frameWidth, frameHeight)
	local contentWidth = frameWidth * (1 - Clip.SafeRight)
	titleLabel.Position = UDim2.fromOffset(side + contentWidth / 2, frameHeight * Clip.SafeTop * 0.6)
	titleLabel.Size = UDim2.fromOffset(contentWidth, frameHeight * Clip.SafeTop)
	watermark.Position = UDim2.fromOffset(side + contentWidth / 2, frameHeight * (1 - Clip.SafeBottom) + 24)
	watermark.Size = UDim2.fromOffset(contentWidth, 40)
end

local function playReplay()
	local view = TableViewController.seatedView()
	if not view or not TableViewController.replay(view) then
		return
	end
	cinematic = false
	local camera = Workspace.CurrentCamera
	camera.FieldOfView = Clip.CameraFov
	camera.CFrame = verticalCamera(view)
end

local function close()
	if not active then
		return
	end
	active, cinematic = false, false
	clipGui.Enabled = false
	for _, gui in hiddenGuis do
		gui.Enabled = true
	end
	table.clear(hiddenGuis)
	TableViewController.resetCamera()
end

local function open()
	local view = TableViewController.seatedView()
	if active or not view or not view.lastShot or view.playback then
		return
	end
	active = true
	offerUntil = 0
	clipHype = view.lastShot.hype
	for _, gui in player:WaitForChild("PlayerGui"):GetChildren() do
		if gui:IsA("ScreenGui") and gui ~= clipGui and gui.Enabled then
			gui.Enabled = false
			table.insert(hiddenGuis, gui)
		end
	end
	local title = if clipHype then ShotClassifier.byId(clipHype.titleId) else nil
	titleLabel.Text = if title then `{title.hanzi}\n{Text.get(title.nameKey)}` else ""
	watermark.Text = Game.Name
	layout()
	clipGui.Enabled = true
	Remotes.Event("ClipOpened"):FireServer()
	playReplay()
end

-- Closing shot: the avatar's face and a reaction.
local function closeUp()
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head then
		return
	end
	cinematic = true
	local camera = Workspace.CurrentCamera
	camera.FieldOfView = 40
	local front = head.CFrame * CFrame.new(0, 0.6, -6)
	camera.CFrame = CFrame.lookAt(front.Position, head.Position)
	if humanoid then
		local title = if clipHype then ShotClassifier.byId(clipHype.titleId) else nil
		local anti = title ~= nil and title.kind == "Anti"
		pcall(function()
			humanoid:PlayEmote(if anti then Clip.FailEmote else Clip.WinEmote)
		end)
	end
	task.delay(Clip.CinematicSeconds, function()
		local view = TableViewController.seatedView()
		if active and cinematic and view then
			cinematic = false
			camera.FieldOfView = Clip.CameraFov
			camera.CFrame = verticalCamera(view)
		end
	end)
end

local function screenshot()
	pcall(function()
		CaptureService:CaptureScreenshot(function(contentId)
			pcall(function()
				CaptureService:PromptSaveCapturesToGallery({ contentId }, function() end)
			end)
		end)
	end)
	Remotes.Event("ClipScreenshot"):FireServer()
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")

	offerGui = Instance.new("ScreenGui")
	offerGui.Name = "ClipOffer"
	offerGui.ResetOnSpawn = false
	offerGui.DisplayOrder = 3
	offerButton = Instance.new("TextButton")
	offerButton.Name = "ClipButton"
	offerButton.AnchorPoint = Vector2.new(1, 1)
	offerButton.Position = UDim2.new(1, -24, 1, -24)
	offerButton.Size = UDim2.fromOffset(120, 52)
	offerButton.BorderSizePixel = 0
	offerButton.Font = Enum.Font.GothamBlack
	offerButton.TextSize = 22
	offerButton.TextColor3 = DARK
	offerButton.Text = Text.get("CLIP_BUTTON")
	offerButton.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = offerButton
	offerButton.Parent = offerGui
	offerButton.Activated:Connect(open)
	offerGui.Parent = playerGui

	clipGui = Instance.new("ScreenGui")
	clipGui.Name = "ClipMode"
	clipGui.ResetOnSpawn = false
	clipGui.IgnoreGuiInset = true
	clipGui.DisplayOrder = 30
	clipGui.Enabled = false
	barLeft = Instance.new("Frame")
	barLeft.Name = "BarLeft"
	barLeft.BackgroundColor3 = Color3.new(0, 0, 0)
	barLeft.BorderSizePixel = 0
	barLeft.Parent = clipGui
	barRight = barLeft:Clone()
	barRight.Name = "BarRight"
	barRight.Parent = clipGui
	frameOutline = Instance.new("Frame")
	frameOutline.Name = "Frame"
	frameOutline.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = frameOutline
	frameOutline.Parent = clipGui
	titleLabel = textLabel("Title", clipGui, 40, GOLD)
	watermark = textLabel("Watermark", clipGui, 26, IVORY)
	watermark.TextTransparency = 0.15

	sideButton("ReplayButton", "CLIP_REPLAY", 0, playReplay)
	sideButton("ScreenshotButton", "CLIP_SCREENSHOT", 1, screenshot)
	sideButton("CloseButton", "CLIP_CLOSE", 2, close)
	local hint = textLabel("Hint", barLeft, 16, IVORY)
	hint.Font = Enum.Font.GothamBold
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 40)
	hint.Size = UDim2.new(1, -20, 0, 120)
	hint.Text = Text.get("CLIP_HINT")
	clipGui.Parent = playerGui
end

local ClipController = {}

function ClipController.Init()
	buildGui()
end

function ClipController.Start()
	TableViewController.PlaybackFinished:Connect(function(tableId, hype)
		local view = TableViewController.seatedView()
		if not view or view.id ~= tableId then
			return
		end
		if active then
			closeUp() -- the replay ended
			return
		end
		offerUntil = os.clock() + Clip.OfferSeconds
		offerHype = hype ~= nil
		-- Own titled shot: the avatar reacts at the table, everyone sees it.
		if hype and hype.playerName == player.DisplayName then
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local title = ShotClassifier.byId(hype.titleId)
			if humanoid and title then
				pcall(function()
					humanoid:PlayEmote(if title.kind == "Anti" then Clip.FailEmote else Clip.WinEmote)
				end)
			end
		end
	end)
	TableViewController.SeatChanged:Connect(function(tableId)
		if not tableId then
			close()
			offerUntil = 0
		end
	end)
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if active then
			layout()
		end
	end)
	RunService.Heartbeat:Connect(function()
		local show = not active and os.clock() < offerUntil
		offerButton.Visible = show
		offerButton.BackgroundColor3 = if offerHype then GOLD else IVORY
	end)
end

return ClipController
