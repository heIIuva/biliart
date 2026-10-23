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
}

export type PlayerLine = { name: string, groupKey: string?, active: boolean }

export type Hud = {
	setVisible: (visible: boolean) -> (),
	showPicker: (visible: boolean) -> (),
	showSearching: (visible: boolean) -> (),
	showStatus: (left: PlayerLine?, right: PlayerLine?) -> (),
	setTimer: (share: number) -> (),
	setHint: (key: string?) -> (),
	toast: (key: string) -> (),
	showResult: (titleKey: string?, reasonKey: string?) -> (),
	resultAdButton: TextButton, -- hidden until an ad is available
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

	-- Level picker.
	local picker = frame("Picker", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 420),
		Visible = false,
		Active = true,
	})
	corner(picker, 0.08)
	label("Title", picker, { Text = Text.get("MATCH_VS_BOT"), Size = UDim2.new(1, 0, 0, 50), TextSize = 22 })
	for i, level in { "Easy", "Medium", "Hard" } do
		button(`{level}Button`, picker, `LEVEL_{string.upper(level)}`, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 50 + (i - 1) * 60),
			Size = UDim2.fromOffset(260, 50),
			BackgroundColor3 = if i == 3 then RED else DARK,
		}, function()
			callbacks.onStart(level)
		end)
	end
	for i, mode in { "Casual", "Ranked" } do
		button(`{mode}Button`, picker, if mode == "Casual" then "MATCH_VS_PLAYER" else "MATCH_RANKED", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 236 + (i - 1) * 60),
			Size = UDim2.fromOffset(260, 50),
			BackgroundColor3 = Color3.fromRGB(120, 80, 20),
		}, function()
			callbacks.onStart(mode)
		end)
	end
	button("PickerLeaveButton", picker, "HUD_LEAVE", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 360),
		Size = UDim2.fromOffset(260, 48),
		BackgroundColor3 = Color3.fromRGB(60, 60, 60),
	}, callbacks.onLeave)

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
