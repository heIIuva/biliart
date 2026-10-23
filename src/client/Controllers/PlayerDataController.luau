--!strict
-- The local player's data snapshot from the server (read-only on the client) and toasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Game.Progression)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Config.Strings)
local Text = require(Shared.Util.Text)
local Kit = require(script.Parent.Parent.UI.Kit)

local MAX_TOASTS = 4
local TOAST_SECONDS = 3

local data: Progression.PlayerData? = nil
local toastList: Frame

local PlayerDataController = {
	Changed = Signal.new(), -- (data)
}

function PlayerDataController.get(): Progression.PlayerData?
	return data
end

local function toast(message: Remotes.Notification)
	local values: { [string]: any } = {}
	for k, v in (message.values or {}) :: { [string]: any } do
		values[k] = if type(v) == "string" and Strings[v] then Text.get(v) else v
	end
	local label = Kit.label("Toast", toastList, Text.format(message.key, values), {
		Size = UDim2.fromOffset(320, 36),
		BackgroundColor3 = Kit.DARK,
		BackgroundTransparency = 0.2,
		TextColor3 = Kit.GOLD,
	})
	Kit.corner(label, 0.3)
	local toasts = {}
	for _, child in toastList:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(toasts, child)
		end
	end
	if #toasts > MAX_TOASTS then
		toasts[1]:Destroy()
	end
	task.delay(TOAST_SECONDS, function()
		local tween =
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween.Completed:Once(function()
			label:Destroy()
		end)
		tween:Play()
	end)
end

function PlayerDataController.Init()
	local gui = Kit.screen("Toasts", 15)
	toastList = Kit.frame("List", gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 120),
		Size = UDim2.fromOffset(320, 200),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = toastList
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function PlayerDataController.Start()
	Remotes.Event("PlayerData").OnClientEvent:Connect(function(snapshot: Progression.PlayerData)
		data = snapshot
		PlayerDataController.Changed:Fire(snapshot)
	end)
	Remotes.Event("Notify").OnClientEvent:Connect(toast)
end

return PlayerDataController
