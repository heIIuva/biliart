--!strict
-- First-session tutorial (GDD 9.5): offers a rigged first match (the first break is a TIGER),
-- then shows four short hints: aim, power, spin, ball in hand. Can be skipped.
-- "Done" is saved in the player data (finished or skipped).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Text = require(Shared.Util.Text)
local MatchController = require(script.Parent.MatchController)
local PlayerDataController = require(script.Parent.PlayerDataController)
local TableViewController = require(script.Parent.TableViewController)

local GOLD = Color3.fromRGB(240, 190, 60)
local RED = Color3.fromRGB(190, 30, 30)
local DARK = Color3.fromRGB(20, 16, 14)
local IVORY = Color3.fromRGB(245, 243, 230)
local SPIN_HINT_SECONDS = 6

type Step = "Off" | "Aim" | "Power" | "Spin" | "BallInHand" | "Done"

local step: Step = "Off"
local spinShownAt = 0
local hint: TextLabel
local offer: Frame

local function button(parent: Instance, name: string, key: string, color: Color3, x: number, onActivated: () -> ())
	local b = Instance.new("TextButton")
	b.Name = name
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(x, 0, 1, -16)
	b.Size = UDim2.fromOffset(150, 48)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 20
	b.TextColor3 = IVORY
	b.Text = Text.get(key)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = b
	b.Parent = parent
	b.Activated:Connect(onActivated)
end

local function buildGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5

	offer = Instance.new("Frame")
	offer.Name = "Offer"
	offer.AnchorPoint = Vector2.new(0.5, 0.5)
	offer.Position = UDim2.fromScale(0.5, 0.5)
	offer.Size = UDim2.fromOffset(380, 170)
	offer.BackgroundColor3 = DARK
	offer.BackgroundTransparency = 0.15
	offer.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.08, 0)
	corner.Parent = offer
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -20, 0, 90)
	title.Position = UDim2.fromOffset(10, 0)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 22
	title.TextWrapped = true
	title.TextColor3 = GOLD
	title.Text = Text.get("TUTORIAL_OFFER")
	title.Parent = offer
	button(offer, "StartButton", "TUTORIAL_START", RED, 0.28, function()
		offer.Visible = false
		step = "Aim"
		Remotes.Event("StartTutorial"):FireServer()
	end)
	button(offer, "SkipButton", "TUTORIAL_SKIP", Color3.fromRGB(60, 60, 60), 0.72, function()
		offer.Visible = false
		step = "Done"
		Remotes.Event("TutorialDone"):FireServer()
	end)
	offer.Parent = gui

	hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -84)
	hint.Size = UDim2.fromOffset(640, 44)
	hint.BackgroundColor3 = DARK
	hint.BackgroundTransparency = 0.2
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 20
	hint.TextColor3 = GOLD
	hint.Visible = false
	hint.Parent = gui

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local HINT_KEYS: { [Step]: string } = {
	Aim = "TUTORIAL_AIM",
	Power = "TUTORIAL_POWER",
	Spin = "TUTORIAL_SPIN",
	BallInHand = "TUTORIAL_BALL_IN_HAND",
}

local function update()
	local key = HINT_KEYS[step]
	local myTurn = MatchController.canShoot()
	if step == "Spin" and os.clock() - spinShownAt > SPIN_HINT_SECONDS then
		step = "BallInHand"
		Remotes.Event("TutorialDone"):FireServer() -- the newcomer has seen the essentials
	end
	if step == "BallInHand" then
		local match = MatchController.current()
		local show = myTurn and match ~= nil and match.ballInHand and not match.isBreak
		hint.Visible = show
		if show then
			hint.Text = Text.get("TUTORIAL_BALL_IN_HAND")
		end
		return
	end
	hint.Visible = key ~= nil and myTurn
	if key then
		hint.Text = Text.get(key)
	end
end

local TutorialController = {}

function TutorialController.Init()
	buildGui()
end

function TutorialController.Start()
	local offered = false
	PlayerDataController.Changed:Connect(function(data)
		if not offered then
			offered = true
			offer.Visible = not data.tutorialDone
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		local press = input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		if step == "Aim" and press and not processed and MatchController.canShoot() then
			step = "Power"
		end
	end)
	TableViewController.ShotStarted:Connect(function()
		if step == "Power" or step == "Aim" then
			step = "Spin"
			spinShownAt = math.huge -- starts counting on the next own turn
		end
	end)
	TableViewController.SeatChanged:Connect(function(tableId)
		if not tableId and step ~= "Off" and step ~= "Done" then
			step = "Done"
			hint.Visible = false
			Remotes.Event("TutorialDone"):FireServer()
		end
	end)
	RunService.Heartbeat:Connect(function()
		if step == "Spin" and spinShownAt == math.huge and MatchController.canShoot() then
			spinShownAt = os.clock()
		end
		update()
	end)
end

return TutorialController
