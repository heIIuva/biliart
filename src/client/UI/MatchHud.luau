--!strict
-- Match screens at the table: bot level picker, top status bar (players, groups, whose turn,
-- turn timer), hints, short outcome toasts and the result panel. Texts come from localization keys.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Text = require(Shared.Util.Text)

local DARK = Color3.fromRGB(20, 16, 14)
local GOLD = Color3.fromRGB(240, 190, 60)
local RED = Color3.fromRGB(190, 30, 30)
local IVORY = Color3.fromRGB(245, 243, 230)
local TOAST_SECONDS = 2.5

export type Callbacks = {
	onStart: (level: string) -> (), -- bot level, or "Casual" / "Ranked" / "Cancel"
	onAgain: () -> (),
	onLeave: () -> (),
	onAd: () -> (), -- "watch an ad: x2 reward" on the result panel
	onSuper: () -> (), -- chaos: toggle the Tiger super shot for the next shot
	onSandbox: (action: string) -> (), -- "rerack" | "clear" | "hideUi" | "camera"
}

export type PlayerLine = { name: string, groupKey: string?, active: boolean }

export type Hud = {
	setVisible: (visible: boolean) -> (),
	showPicker: (visible: boolean) -> (),
	showSearching: (visible: boolean) -> (),
	showStatus: (left: PlayerLine?, right: PlayerLine?) -> (),
	setTimer: (share: number) -> (),
	setHint: (key: string?) -> (),
	setHintText: (text: string) -> (),
	toast: (key: string) -> (),
	showResult: (titleKey: string?, reasonKey: string?) -> (),
	resultAdButton: TextButton, -- hidden until an ad is available
	setChaos: (meter: number?, armed: boolean, superOn: boolean) -> (), -- nil meter hides the chaos bar
	setSandbox: (visible: boolean) -> (),
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
	f.BackgroundTransparency = 0.2
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function label(name: string, parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = IVORY
	l.TextSize = 18
	l.Text = ""
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

local function button(
	name: string,
	parent: Instance,
	key: string,
	props: { [string]: any },
	onActivated: () -> ()
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BorderSizePixel = 0
	b.BackgroundColor3 = RED
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = IVORY
	b.TextSize = 20
	b.Text = Text.get(key)
	for k, v in props do
		(b :: any)[k] = v
	end
	corner(b, 0.25)
	b.Parent = parent
	b.Activated:Connect(onActivated)
	return b
end

local MatchHud = {}

function MatchHud.new(callbacks: Callbacks): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "MatchHud"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 1 -- above the aiming controls
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	-- Mode picker: a scrolling list so it fits a landscape phone.
	local picker = frame("Picker", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 340, 0.82, 0),
		Visible = false,
		Active = true,
	})
	corner(picker, 0.06)
	label("Title", picker, { Text = Text.get("MATCH_VS_BOT"), Size = UDim2.new(1, 0, 0, 44), TextSize = 22 })
	local options = Instance.new("ScrollingFrame")
	options.Name = "Options"
	options.BackgroundTransparency = 1
	options.BorderSizePixel = 0
	options.Position = UDim2.fromOffset(0, 46)
	options.Size = UDim2.new(1, 0, 1, -52)
	options.AutomaticCanvasSize = Enum.AutomaticSize.Y
	options.CanvasSize = UDim2.new()
	options.ScrollBarThickness = 6
	options.Parent = picker
	local optionsLayout = Instance.new("UIListLayout")
	optionsLayout.Padding = UDim.new(0, 8)
	optionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	optionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	optionsLayout.Parent = options
	local entries: { { name: string, key: string, payload: string?, color: Color3 } } = {
		{ name = "EasyButton", key = "LEVEL_EASY", payload = "Easy", color = DARK },
		{ name = "MediumButton", key = "LEVEL_MEDIUM", payload = "Medium", color = DARK },
		{ name = "HardButton", key = "LEVEL_HARD", payload = "Hard", color = RED },
		{ name = "CasualButton", key = "MATCH_VS_PLAYER", payload = "Casual", color = Color3.fromRGB(120, 80, 20) },
		{ name = "RankedButton", key = "MATCH_RANKED", payload = "Ranked", color = Color3.fromRGB(120, 80, 20) },
		{ name = "ChaosButton", key = "MATCH_CHAOS", payload = "Chaos", color = Color3.fromRGB(110, 20, 110) },
		{ name = "TrickButton", key = "MATCH_TRICK", payload = "Trick", color = Color3.fromRGB(20, 90, 110) },
		{ name = "SandboxButton", key = "MATCH_SANDBOX", payload = "Sandbox", color = Color3.fromRGB(20, 90, 110) },
		{ name = "PickerLeaveButton", key = "HUD_LEAVE", payload = nil, color = Color3.fromRGB(60, 60, 60) },
	}
	for i, entry in entries do
		local b = button(entry.name, options, entry.key, {
			Size = UDim2.fromOffset(260, 48),
			BackgroundColor3 = entry.color,
		}, function()
			local payload = entry.payload
			if payload then
				callbacks.onStart(payload)
			else
				callbacks.onLeave()
			end
		end)
		b.LayoutOrder = i
	end

	-- Waiting for a human opponent.
	local searching = frame("Searching", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 150),
		Visible = false,
		Active = true,
	})
	corner(searching, 0.08)
	label("Title", searching, { Text = Text.get("MATCH_SEARCHING"), Size = UDim2.new(1, 0, 0, 70), TextSize = 22 })
	button("CancelSearchButton", searching, "MATCH_CANCEL", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 80),
		Size = UDim2.fromOffset(200, 48),
		BackgroundColor3 = Color3.fromRGB(60, 60, 60),
	}, function()
		callbacks.onStart("Cancel")
	end)

	-- Status bar: left player | timer | right player.
	local bar = frame("Status", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(560, 56),
		Visible = false,
	})
	corner(bar, 0.3)
	local function side(name: string, xAlign: Enum.TextXAlignment, position: UDim2): (TextLabel, TextLabel)
		local nameLabel = label(name, bar, {
			Position = position,
			Size = UDim2.fromScale(0.38, 0.55),
			TextXAlignment = xAlign,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local groupLabel = label(name .. "Group", bar, {
			Position = position + UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(0.38, 0.45),
			TextXAlignment = xAlign,
			TextSize = 14,
			TextColor3 = GOLD,
		})
		return nameLabel, groupLabel
	end
	local leftName, leftGroup = side("Left", Enum.TextXAlignment.Left, UDim2.fromScale(0.02, 0))
	local rightName, rightGroup = side("Right", Enum.TextXAlignment.Right, UDim2.fromScale(0.6, 0))
	local timerBack = frame("Timer", bar, {
		BackgroundColor3 = IVORY,
		BackgroundTransparency = 0.8,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.18, 0, 0, 10),
	})
	corner(timerBack, 0.5)
	local timerFill =
		frame("Fill", timerBack, { BackgroundColor3 = GOLD, BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1) })
	corner(timerFill, 0.5)

	local hint = label("Hint", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(560, 28),
		TextSize = 18,
		TextStrokeTransparency = 0.4,
	})

	local toastLabel = label("Toast", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(600, 50),
		TextSize = 30,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0.2,
		TextTransparency = 1,
		TextStrokeColor3 = DARK,
	})

	-- Result panel.
	local result = frame("Result", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 320),
		Visible = false,
		Active = true,
	})
	corner(result, 0.08)
	local resultTitle = label("Title", result, { Size = UDim2.new(1, 0, 0, 70), TextSize = 36, TextColor3 = GOLD })
	local resultReason = label("Reason", result, {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
	})
	button("AgainButton", result, "MATCH_AGAIN", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 125),
		Size = UDim2.fromOffset(280, 50),
	}, callbacks.onAgain)
	local adButton = button("AdButton", result, "AD_MATCH_X2", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 245),
		Size = UDim2.fromOffset(320, 48),
		BackgroundColor3 = Color3.fromRGB(120, 80, 20),
		Visible = false,
	}, function()
		callbacks.onAd()
	end)
	button("ResultLeaveButton", result, "HUD_LEAVE", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 185),
		Size = UDim2.fromOffset(280, 48),
		BackgroundColor3 = Color3.fromRGB(60, 60, 60),
	}, callbacks.onLeave)

	-- Bottom-left mode bar: chaos meter + super shot, or sandbox tools.
	local modeBar = frame("ModeBar", gui, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(440, 48),
		BackgroundTransparency = 1,
	})
	local barLayout = Instance.new("UIListLayout")
	barLayout.FillDirection = Enum.FillDirection.Horizontal
	barLayout.Padding = UDim.new(0, 8)
	barLayout.SortOrder = Enum.SortOrder.LayoutOrder
	barLayout.Parent = modeBar
	local meterBack = frame("Meter", modeBar, { Size = UDim2.fromOffset(150, 48), LayoutOrder = 1, Visible = false })
	corner(meterBack, 0.2)
	local meterFill =
		frame("Fill", meterBack, { BackgroundColor3 = GOLD, BackgroundTransparency = 0, Size = UDim2.fromScale(0, 1) })
	corner(meterFill, 0.2)
	label("Label", meterBack, { Text = Text.get("CHAOS_METER"), Size = UDim2.fromScale(1, 1), TextSize = 14 })
	local superButton = button("SuperButton", modeBar, "CHAOS_SUPER", {
		Size = UDim2.fromOffset(200, 48),
		LayoutOrder = 2,
		Visible = false,
	}, callbacks.onSuper)
	local sandboxButtons: { TextButton } = {}
	for i, entry in
		{
			{ "rerack", "SANDBOX_RERACK" },
			{ "clear", "SANDBOX_CLEAR" },
			{ "hideUi", "SANDBOX_HIDE_UI" },
			{ "camera", "SANDBOX_CAMERA" },
		}
	do
		local b = button(`Sandbox_{entry[1]}`, modeBar, entry[2], {
			Size = UDim2.fromOffset(100, 48),
			LayoutOrder = 10 + i,
			TextSize = 14,
			BackgroundColor3 = Color3.fromRGB(20, 90, 110),
			Visible = false,
		}, function()
			callbacks.onSandbox(entry[1])
		end)
		table.insert(sandboxButtons, b)
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local toastTween: Tween? = nil
	local function fill(nameLabel: TextLabel, groupLabel: TextLabel, line: PlayerLine?)
		nameLabel.Text = if line then line.name else ""
		nameLabel.TextColor3 = if line and line.active then GOLD else IVORY
		groupLabel.Text = if line and line.groupKey then Text.get(line.groupKey) else ""
	end

	return {
		setVisible = function(visible: boolean)
			gui.Enabled = visible
		end,
		showPicker = function(visible: boolean)
			picker.Visible = visible
		end,
		showSearching = function(visible: boolean)
			searching.Visible = visible
		end,
		showStatus = function(left: PlayerLine?, right: PlayerLine?)
			bar.Visible = left ~= nil
			fill(leftName, leftGroup, left)
			fill(rightName, rightGroup, right)
		end,
		setTimer = function(share: number)
			timerFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
			timerFill.BackgroundColor3 = if share < 0.25 then RED else GOLD
		end,
		setHint = function(key: string?)
			hint.Text = if key then Text.get(key) else ""
		end,
		setHintText = function(text: string)
			hint.Text = text
		end,
		toast = function(key: string)
			if toastTween then
				toastTween:Cancel()
			end
			toastLabel.Text = Text.get(key)
			toastLabel.TextTransparency = 0
			toastLabel.TextStrokeTransparency = 0.2
			local tween = TweenService:Create(
				toastLabel,
				TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, TOAST_SECONDS),
				{ TextTransparency = 1, TextStrokeTransparency = 1 }
			)
			toastTween = tween
			tween:Play()
		end,
		resultAdButton = adButton,
		setChaos = function(meter: number?, armed: boolean, superOn: boolean)
			meterBack.Visible = meter ~= nil
			superButton.Visible = meter ~= nil and armed
			meterFill.Size = UDim2.fromScale(meter or 0, 1)
			superButton.BackgroundColor3 = if superOn then GOLD else RED
		end,
		setSandbox = function(visible: boolean)
			for _, b in sandboxButtons do
				b.Visible = visible
			end
		end,
		showResult = function(titleKey: string?, reasonKey: string?)
			if not result.Visible then
				adButton.Visible = false
			end
			result.Visible = titleKey ~= nil
			resultTitle.Text = if titleKey then Text.get(titleKey) else ""
			resultReason.Text = if reasonKey then Text.get(reasonKey) else ""
		end,
	}
end

return MatchHud
