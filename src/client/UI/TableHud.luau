--!strict
-- On-screen controls at the table, mobile first: power bar (left), fine aim wheel (right),
-- spin/elevation panel, stand-up and re-rack buttons. All texts come from localization keys.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Controls = require(Shared.Config.Controls)
local Game = require(Shared.Config.Game)
local Physics = require(Shared.Config.Physics)
local Text = require(Shared.Util.Text)

local BAR_WIDTH = 72 -- px; touch targets stay well above 44 pt
local EDGE = 24
local PANEL_BALL = 220
local DARK = Color3.fromRGB(20, 16, 14)
local GOLD = Color3.fromRGB(240, 190, 60)
local RED = Color3.fromRGB(190, 30, 30)
local IVORY = Color3.fromRGB(245, 243, 230)

export type Callbacks = {
	onPower: (power: number) -> (), -- while dragging the power bar
	onRelease: (power: number) -> (), -- finger lifted from the power bar
	onFine: (deltaRadians: number) -> (),
	onSpin: (spinX: number, spinY: number) -> (),
	onElevation: (radians: number) -> (),
	onLeave: () -> (),
	onRerack: () -> (),
}

export type Hud = {
	setVisible: (visible: boolean) -> (),
	setAimEnabled: (enabled: boolean) -> (), -- hides aiming controls during playback
	setPower: (power: number) -> (),
	setSpin: (spinX: number, spinY: number) -> (),
	setElevation: (radians: number) -> (),
}

local function corner(parent: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

local function frame(name: string, parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = DARK
	f.BackgroundTransparency = 0.25
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function label(parent: Instance, key: string, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = IVORY
	l.TextSize = 16
	l.Text = Text.get(key)
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function button(parent: Instance, key: string, props: { [string]: any }, onActivated: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.BorderSizePixel = 0
	b.BackgroundColor3 = RED
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = IVORY
	b.TextSize = 18
	b.AutoButtonColor = true
	b.Text = Text.get(key)
	for k, v in props do
		(b :: any)[k] = v
	end
	corner(b, 0.25)
	b.Parent = parent
	b.Activated:Connect(onActivated)
	return b
end

-- Follows one touch or mouse press that started on `object` until it is released.
local function drag(object: GuiObject, onMove: (position: Vector3, start: Vector3) -> (), onEnd: (() -> ())?)
	object.InputBegan:Connect(function(input: InputObject)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		if input.UserInputType ~= Enum.UserInputType.Touch and not isMouse then
			return
		end
		local start = input.Position
		onMove(start, start)
		local moved = UserInputService.InputChanged:Connect(function(changed: InputObject)
			if changed == input or (isMouse and changed.UserInputType == Enum.UserInputType.MouseMovement) then
				onMove(changed.Position, start)
			end
		end)
		local ended: RBXScriptConnection
		ended = UserInputService.InputEnded:Connect(function(released: InputObject)
			if released == input or (isMouse and released.UserInputType == Enum.UserInputType.MouseButton1) then
				moved:Disconnect()
				ended:Disconnect()
				if onEnd then
					onEnd()
				end
			end
		end)
	end)
end

local TableHud = {}

function TableHud.new(callbacks: Callbacks): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "TableHud"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	-- Power: pull down from where the finger lands; release to shoot, slide back up to cancel.
	local power = 0
	local powerBar = frame("PowerBar", gui, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, EDGE, 0.5, 0),
		Size = UDim2.new(0, BAR_WIDTH, 0.62, 0),
		Active = true,
	})
	corner(powerBar, 0.2)
	local powerFill = frame("Fill", powerBar, {
		BackgroundColor3 = GOLD,
		BackgroundTransparency = 0,
		Size = UDim2.fromScale(1, 0),
	})
	corner(powerFill, 0.2)
	label(powerBar, "HUD_POWER", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, 4) })

	local function setPower(value: number)
		power = value
		powerFill.Size = UDim2.fromScale(1, value)
	end
	drag(powerBar, function(position, start)
		setPower(math.clamp((position.Y - start.Y) / powerBar.AbsoluteSize.Y, 0, 1))
		callbacks.onPower(power)
	end, function()
		local released = power
		setPower(0)
		callbacks.onRelease(released)
	end)

	-- Fine aim: vertical drag turns the cue slowly.
	local wheel = frame("FineWheel", gui, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -EDGE, 0.5, 0),
		Size = UDim2.new(0, BAR_WIDTH, 0.62, 0),
		Active = true,
	})
	corner(wheel, 0.2)
	for i = 1, 9 do
		frame("Ridge", wheel, {
			BackgroundColor3 = IVORY,
			BackgroundTransparency = 0.6,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, i / 10),
			Size = UDim2.new(0.6, 0, 0, 2),
		})
	end
	label(wheel, "HUD_FINE", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, 4) })
	local lastY = 0
	drag(wheel, function(position, start)
		if position == start then
			lastY = start.Y
			return
		end
		callbacks.onFine(-(position.Y - lastY) * Controls.FineRadiansPerPixel)
		lastY = position.Y
	end)

	-- Spin button shows the current tip offset; opens the panel.
	local spinButton = Instance.new("TextButton")
	spinButton.Name = "SpinButton"
	spinButton.Text = ""
	spinButton.AnchorPoint = Vector2.new(1, 0)
	spinButton.Position = UDim2.new(1, -EDGE, 0, EDGE)
	spinButton.Size = UDim2.fromOffset(BAR_WIDTH, BAR_WIDTH)
	spinButton.BackgroundColor3 = IVORY
	spinButton.BorderSizePixel = 0
	corner(spinButton, 0.5)
	spinButton.Parent = gui
	local spinDotSmall = frame("Dot", spinButton, {
		BackgroundColor3 = RED,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
	})
	corner(spinDotSmall, 0.5)
	label(spinButton, "HUD_SPIN", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, 2) })

	local panel = frame("SpinPanel", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL_BALL + 60, PANEL_BALL + (if Game.ElevationControl then 190 else 120)),
		Visible = false,
		Active = true,
	})
	corner(panel, 0.08)
	local ball = frame("Ball", panel, {
		BackgroundColor3 = IVORY,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 30),
		Size = UDim2.fromOffset(PANEL_BALL, PANEL_BALL),
		Active = true,
	})
	corner(ball, 0.5)
	local spinDot = frame("Dot", ball, {
		BackgroundColor3 = RED,
		BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(28, 28),
	})
	corner(spinDot, 0.5)

	-- The panel ball's rim is the maximum tip offset.
	local function setSpin(spinX: number, spinY: number)
		local u, v = spinX / Physics.MaxTipOffset, spinY / Physics.MaxTipOffset
		spinDot.Position = UDim2.fromScale(0.5 + u / 2, 0.5 - v / 2)
		spinDotSmall.Position = UDim2.fromScale(0.5 + u / 2, 0.5 - v / 2)
	end
	drag(ball, function(position)
		local size = ball.AbsoluteSize
		local u = (position.X - ball.AbsolutePosition.X) / size.X * 2 - 1
		local v = -((position.Y - ball.AbsolutePosition.Y) / size.Y * 2 - 1)
		local length = math.sqrt(u * u + v * v)
		if length > 1 then
			u, v = u / length, v / length
		end
		local spinX, spinY = u * Physics.MaxTipOffset, v * Physics.MaxTipOffset
		setSpin(spinX, spinY)
		callbacks.onSpin(spinX, spinY)
	end)

	local elevationKnob: Frame? = nil
	local function setElevation(radians: number)
		if elevationKnob then
			elevationKnob.Position = UDim2.fromScale(radians / Physics.MaxElevation, 0.5)
		end
	end
	if Game.ElevationControl then
		label(panel, "HUD_ELEVATION", {
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.fromOffset(0, PANEL_BALL + 40),
		})
		local slider = frame("Elevation", panel, {
			BackgroundColor3 = IVORY,
			BackgroundTransparency = 0.7,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, PANEL_BALL + 70),
			Size = UDim2.fromOffset(PANEL_BALL, 44),
			Active = true,
		})
		corner(slider, 0.3)
		local knob = frame("Knob", slider, {
			BackgroundColor3 = GOLD,
			BackgroundTransparency = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(28, 40),
		})
		corner(knob, 0.3)
		elevationKnob = knob
		drag(slider, function(position)
			local share = math.clamp((position.X - slider.AbsolutePosition.X) / slider.AbsoluteSize.X, 0, 1)
			setElevation(share * Physics.MaxElevation)
			callbacks.onElevation(share * Physics.MaxElevation)
		end)
	end

	local buttonsY = if Game.ElevationControl then PANEL_BALL + 126 else PANEL_BALL + 50
	button(panel, "HUD_SPIN_RESET", {
		Name = "SpinResetButton",
		Position = UDim2.fromOffset(20, buttonsY),
		Size = UDim2.new(0.5, -30, 0, 48),
		BackgroundColor3 = DARK,
	}, function()
		setSpin(0, 0)
		setElevation(0)
		callbacks.onSpin(0, 0)
		callbacks.onElevation(0)
	end)
	button(panel, "HUD_CLOSE", {
		Name = "SpinCloseButton",
		Position = UDim2.new(0.5, 10, 0, buttonsY),
		Size = UDim2.new(0.5, -30, 0, 48),
	}, function()
		panel.Visible = false
	end)
	spinButton.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end)

	-- Bottom center: the top-left corner belongs to the Roblox chat window, which swallows input there.
	button(gui, "HUD_LEAVE", {
		Name = "LeaveButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(0.5, -6, 1, -EDGE),
		Size = UDim2.fromOffset(150, 48),
	}, callbacks.onLeave)
	button(gui, "HUD_RERACK", {
		Name = "RerackButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, 6, 1, -EDGE),
		Size = UDim2.fromOffset(200, 48),
		BackgroundColor3 = DARK,
	}, callbacks.onRerack)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	return {
		setVisible = function(visible: boolean)
			gui.Enabled = visible
			if not visible then
				panel.Visible = false
			end
		end,
		setAimEnabled = function(enabled: boolean)
			powerBar.Visible = enabled
			wheel.Visible = enabled
			spinButton.Visible = enabled
			if not enabled then
				panel.Visible = false
			end
		end,
		setPower = setPower,
		setSpin = setSpin,
		setElevation = setElevation,
	}
end

return TableHud
