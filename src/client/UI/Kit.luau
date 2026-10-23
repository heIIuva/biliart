--!strict
-- Small helpers for building UI in code with the game's look (red / gold / black).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Text = require(Shared.Util.Text)

local Kit = {
	DARK = Color3.fromRGB(20, 16, 14),
	GOLD = Color3.fromRGB(240, 190, 60),
	RED = Color3.fromRGB(190, 30, 30),
	IVORY = Color3.fromRGB(245, 243, 230),
	GREY = Color3.fromRGB(60, 60, 60),
}

local function apply(instance: Instance, props: { [string]: any }?)
	for k, v in (props or {}) :: { [string]: any } do
		(instance :: any)[k] = v
	end
end

function Kit.corner(parent: GuiObject, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.15, 0)
	c.Parent = parent
end

function Kit.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order or 0
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	return gui
end

function Kit.frame(name: string, parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Kit.DARK
	f.BackgroundTransparency = 0.15
	apply(f, props)
	f.Parent = parent
	return f
end

-- A label; `text` is shown as is (pass Text.get(...) for localized strings).
function Kit.label(name: string, parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = Kit.IVORY
	l.TextSize = 18
	l.Text = text
	apply(l, props)
	l.Parent = parent
	return l
end

-- A button with a localized caption.
function Kit.button(
	name: string,
	parent: Instance,
	key: string,
	props: { [string]: any }?,
	onActivated: () -> ()
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Kit.RED
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Kit.IVORY
	b.TextSize = 18
	b.AutoButtonColor = true
	b.Text = Text.get(key)
	apply(b, props)
	Kit.corner(b, 0.25)
	b.Parent = parent
	b.Activated:Connect(onActivated)
	return b
end

-- A centered panel with a title and a scrolling list; returns the panel and the list.
function Kit.panel(name: string, parent: Instance, titleKey: string, onClose: () -> ()): (Frame, ScrollingFrame)
	local panel = Kit.frame(name, parent, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.75),
		Visible = false,
		Active = true,
	})
	Kit.corner(panel, 0.04)
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(820, 560)
	size.Parent = panel
	Kit.label("Title", panel, Text.get(titleKey), {
		Size = UDim2.new(1, -140, 0, 48),
		Position = UDim2.fromOffset(16, 4),
		TextSize = 24,
		TextColor3 = Kit.GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Kit.button("Close", panel, "MENU_CLOSE", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		Size = UDim2.fromOffset(110, 40),
		BackgroundColor3 = Kit.GREY,
	}, onClose)
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, 58)
	list.Size = UDim2.new(1, -24, 1, -70)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollBarThickness = 6
	list.Parent = panel
	return panel, list
end

function Kit.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

return Kit
