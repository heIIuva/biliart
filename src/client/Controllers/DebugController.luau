--!strict
-- Studio-only debug panel (GDD phase 4): "set up the scenario for title X" — the server lays out a
-- known position on the player's table and plays the shot that earns the title.
-- Developer tool, never shown in live games, so its labels are raw title ids.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Titles = require(Shared.Config.Titles)

local DebugController = {}

function DebugController.Start()
	if not RunService:IsStudio() then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DebugPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20

	local list = Instance.new("ScrollingFrame")
	list.Name = "Titles"
	list.AnchorPoint = Vector2.new(1, 1)
	list.Position = UDim2.new(1, -8, 1, -64)
	list.Size = UDim2.fromOffset(150, 260)
	list.CanvasSize = UDim2.fromOffset(0, #Titles * 30)
	list.BackgroundTransparency = 0.3
	list.Visible = false
	local layout = Instance.new("UIListLayout")
	layout.Parent = list
	for _, title in Titles do
		local b = Instance.new("TextButton")
		b.Name = title.id
		b.Size = UDim2.new(1, 0, 0, 28)
		b.Text = title.id
		b.Parent = list
		b.Activated:Connect(function()
			Remotes.Event("Debug"):FireServer({ action = "title", id = title.id })
		end)
	end
	list.Parent = gui

	local toggle = Instance.new("TextButton")
	toggle.Name = "Toggle"
	toggle.AnchorPoint = Vector2.new(1, 1)
	toggle.Position = UDim2.new(1, -8, 1, -16)
	toggle.Size = UDim2.fromOffset(70, 40)
	toggle.Text = "DBG"
	toggle.Parent = gui
	toggle.Activated:Connect(function()
		list.Visible = not list.Visible
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return DebugController
