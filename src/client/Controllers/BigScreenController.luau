--!strict
-- The big screen behind the King table: a live top-down map of the balls plus whose turn it is,
-- so spectators can follow the match from the lobby. Drawn only while the screen is near.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local TableSpace = require(Shared.World.TableSpace)
local Text = require(Shared.Util.Text)
local Kit = require(script.Parent.Parent.UI.Kit)
local TableViewController = require(script.Parent.TableViewController)

local DRAW_DISTANCE = 160
local BALL_COLORS: { [number]: Color3 } = {
	[0] = Color3.fromRGB(245, 243, 230),
	[1] = Color3.fromRGB(250, 200, 20),
	[2] = Color3.fromRGB(25, 60, 200),
	[3] = Color3.fromRGB(210, 30, 30),
	[4] = Color3.fromRGB(100, 30, 150),
	[5] = Color3.fromRGB(240, 110, 20),
	[6] = Color3.fromRGB(20, 130, 60),
	[7] = Color3.fromRGB(120, 20, 30),
	[8] = Color3.fromRGB(15, 15, 15),
}

local screenPart: BasePart? = nil
local cloth: Frame? = nil
local status: TextLabel? = nil
local dots: { [number]: Frame } = {}
local tableId = ""

local function build(part: BasePart)
	screenPart = part
	tableId = part:GetAttribute("ScreenFor") :: string
	local gui = Instance.new("SurfaceGui")
	gui.Name = "KingScreen"
	gui.Adornee = part
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	status = Kit.label("Status", gui, "", {
		Size = UDim2.fromScale(1, 0.15),
		TextScaled = true,
		TextColor3 = Kit.GOLD,
	})
	local frame = Kit.frame("Cloth", gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromScale(0.9, 0.8),
		BackgroundColor3 = Color3.fromRGB(150, 24, 32),
		BackgroundTransparency = 0,
	})
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 2
	ratio.Parent = frame
	cloth = frame
end

local function dot(id: number): Frame
	local existing = dots[id]
	if existing then
		return existing
	end
	local d = Kit.frame(`Ball{id}`, cloth :: Frame, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromScale(0.026, 0.052),
		BackgroundColor3 = BALL_COLORS[if id >= 9 then id - 8 else id],
		BackgroundTransparency = 0,
	})
	Kit.corner(d, 0.5)
	if id >= 9 then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 2
		stroke.Parent = d
	end
	dots[id] = d
	return d
end

local function update()
	local part, frame = screenPart, cloth
	local camera = Workspace.CurrentCamera
	if not part or not frame or (camera.CFrame.Position - part.Position).Magnitude > DRAW_DISTANCE then
		return
	end
	local view = TableViewController.view(tableId)
	if not view then
		return
	end
	local g = view.geometry
	for id, ballPart in view.parts do
		local d = dot(id)
		d.Visible = ballPart.Parent ~= nil
		local x, y = TableSpace.toTable(view.surface, ballPart.Position)
		d.Position = UDim2.fromScale(0.5 + x / (2 * g.halfLength), 0.5 - y / (2 * g.halfWidth))
	end
end

local BigScreenController = {}

function BigScreenController.Start()
	local function watch(child: Instance)
		if child:IsA("BasePart") and child:GetAttribute("ScreenFor") then
			build(child)
		end
	end
	for _, child in Workspace:GetChildren() do
		watch(child)
	end
	Workspace.ChildAdded:Connect(watch)
	Remotes.Event("MatchState").OnClientEvent:Connect(function(snapshot: Remotes.MatchSnapshot)
		local label = status
		if not label or snapshot.tableId ~= tableId then
			return
		end
		local a, b = snapshot.players[1], snapshot.players[2]
		label.Text = if a
				and b
				and snapshot.phase ~= "Idle"
			then `👑 {a.name}  —  {b.name}`
			else Text.get("PROMPT_KING")
	end)
	RunService.Heartbeat:Connect(update)
end

return BigScreenController
