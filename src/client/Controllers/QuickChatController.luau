--!strict
-- Quick chat (GDD 15): ready-made phrases and emotes from a small menu; shown above the sender's
-- head to everyone. Emotes also play an animation on the sender's avatar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuickChat = require(Shared.Config.QuickChat)
local Remotes = require(Shared.Net.Remotes)
local Text = require(Shared.Util.Text)
local Kit = require(script.Parent.Parent.UI.Kit)
local Sfx = require(script.Parent.Parent.Util.Sfx)

local player = Players.LocalPlayer

local function find(id: string): QuickChat.Entry?
	for _, list in { QuickChat.Phrases, QuickChat.Emotes } do
		for _, entry in list do
			if entry.id == id then
				return entry
			end
		end
	end
	return nil
end

local function show(message: Remotes.QuickChatMessage)
	local entry = find(message.id)
	local sender = Players:GetPlayerByUserId(message.userId)
	local head = sender and sender.Character and sender.Character:FindFirstChild("Head")
	if not entry or not sender or not head then
		return
	end
	local old = head:FindFirstChild("QuickChat")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "QuickChat"
	gui.Size = UDim2.fromOffset(240, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = true
	local label = Kit.label("Text", gui, Text.get(entry.key), {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.DARK,
		BackgroundTransparency = 0.2,
		TextColor3 = Kit.GOLD,
		TextScaled = true,
	})
	Kit.corner(label, 0.3)
	gui.Parent = head
	task.delay(QuickChat.ShowSeconds, function()
		gui:Destroy()
	end)
	if entry.sound then
		Sfx.play(entry.sound, 0.8)
	end
	if entry.emote and sender == player then
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			pcall(function()
				humanoid:PlayEmoteAsync(entry.emote :: string)
			end)
		end
	end
end

local QuickChatController = {}

function QuickChatController.Init()
	local gui = Kit.screen("QuickChat", 4)
	local list = Kit.frame("List", gui, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -150, 1, -84),
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	Kit.corner(list, 0.06)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list
	local order = 0
	for _, entries in { QuickChat.Phrases, QuickChat.Emotes } do
		for _, entry in entries do
			order += 1
			Kit.button(entry.id, list, entry.key, {
				Size = UDim2.new(1, 0, 0, 40),
				LayoutOrder = order,
				BackgroundColor3 = if entry.emote then Color3.fromRGB(120, 80, 20) else Kit.RED,
			}, function()
				list.Visible = false
				Remotes.Event("QuickChat"):FireServer(entry.id)
			end)
		end
	end
	Kit.button("ChatButton", gui, "MENU_CHAT", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -150, 1, -24),
		Size = UDim2.fromOffset(110, 52),
	}, function()
		list.Visible = not list.Visible
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
end

function QuickChatController.Start()
	Remotes.Event("QuickChatShown").OnClientEvent:Connect(show)
end

return QuickChatController
