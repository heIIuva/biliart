--!strict
-- Aiming and shooting at the seated table.
-- Touch: the finger on the table points the cue; power bar on the left, fine wheel on the right.
-- Mouse: the cursor points the cue; hold LMB and pull back for power, release to shoot
-- (RMB cancels); wheel / arrow keys fine-tune. Only the intent goes to the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AimPredictor = require(Shared.Pool.AimPredictor)
local Controls = require(Shared.Config.Controls)
local Physics = require(Shared.Config.Physics)
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local Remotes = require(Shared.Net.Remotes)
local TableSpace = require(Shared.World.TableSpace)
local TableHud = require(script.Parent.Parent.UI.TableHud)
local TableViewController = require(script.Parent.TableViewController)

type View = TableViewController.View

local LINE_THICKNESS = 0.006 -- meters
local CUE_DIAMETER = 0.025

local aim = { angle = 0, power = 0, spinX = 0, spinY = 0, elevation = 0 }
local waitingSince: number? = nil -- shot sent, result not arrived yet
local aimTouch: InputObject? = nil
local pullStart: { x: number, y: number }? = nil
local hud: TableHud.Hud
local visuals: Folder
local guideMain: Part
local guideTarget: Part
local guideCue: Part
local ghost: Part
local cueStick: Part

local function cueBall(view: View): PoolPhysics.BallState?
	for _, b in view.balls do
		if b.id == 0 and b.status == "Stationary" then
			return b
		end
	end
	return nil
end

-- The seated view, if the player may aim right now.
local function aimingView(): View?
	local view = TableViewController.seatedView()
	if view and view.playback == nil and waitingSince == nil and cueBall(view) then
		return view
	end
	return nil
end

local function visualPart(name: string, shape: Enum.PartType, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 255, 255)
	p.Transparency = transparency
	p.Parent = visuals
	return p
end

local function setLine(line: Part, from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 1e-3 then
		line.Transparency = 1
		return
	end
	local thickness = TableSpace.studs(LINE_THICKNESS)
	line.Transparency = 0.15
	line.Size = Vector3.new(thickness, thickness, length)
	line.CFrame = CFrame.lookAt((from + to) / 2, to)
end

local function drawAim(view: View, cue: PoolPhysics.BallState)
	local R = view.geometry.ballRadius
	local surface = view.surface
	local prediction = AimPredictor.predict(view.geometry, view.balls, aim.angle)
	local from = TableSpace.toWorld(surface, cue.x, cue.y, R)
	local contact = TableSpace.toWorld(surface, prediction.ghostX, prediction.ghostY, R)

	setLine(guideMain, from, contact)
	ghost.Transparency = if prediction.kind == "None" then 1 else 0.6
	ghost.Position = contact

	local targetLength = if prediction.kind == "Ball" then Controls.GuideObjectMeters else 0
	local targetStartX = prediction.ghostX + prediction.targetDirX * 2 * R
	local targetStartY = prediction.ghostY + prediction.targetDirY * 2 * R
	setLine(
		guideTarget,
		TableSpace.toWorld(surface, targetStartX, targetStartY, R),
		TableSpace.toWorld(
			surface,
			targetStartX + prediction.targetDirX * targetLength,
			targetStartY + prediction.targetDirY * targetLength,
			R
		)
	)
	setLine(
		guideCue,
		contact,
		TableSpace.toWorld(
			surface,
			prediction.ghostX + prediction.cueDirX * Controls.GuideCueMeters,
			prediction.ghostY + prediction.cueDirY * Controls.GuideCueMeters,
			R
		)
	)

	-- Cue stick: behind the ball along the aim, tilted by elevation, pulled back with power.
	local flat = TableSpace.direction(surface, math.cos(aim.angle), math.sin(aim.angle))
	local into = flat * math.cos(aim.elevation) - surface.UpVector * math.sin(aim.elevation)
	local back = R + Controls.CueTipGapMeters + aim.power * Controls.CuePullbackMeters
	local tip = from - into * TableSpace.studs(back)
	local length = TableSpace.studs(Controls.CueLengthMeters)
	local center = tip - into * (length / 2)
	cueStick.Size = Vector3.new(length, TableSpace.studs(CUE_DIAMETER), TableSpace.studs(CUE_DIAMETER))
	cueStick.CFrame = CFrame.lookAt(center, center + into) * CFrame.Angles(0, math.pi / 2, 0)
end

-- Table point (meters) under a screen position, on the plane of the ball centers.
local function tablePoint(view: View, screen: Vector3): (number?, number?)
	local ray = Workspace.CurrentCamera:ScreenPointToRay(screen.X, screen.Y)
	local up = view.surface.UpVector
	local denominator = ray.Direction:Dot(up)
	if math.abs(denominator) < 1e-6 then
		return nil, nil
	end
	local plane = view.surface.Position + up * TableSpace.studs(view.geometry.ballRadius)
	local distance = (plane - ray.Origin):Dot(up) / denominator
	if distance < 0 then
		return nil, nil
	end
	return TableSpace.toTable(view.surface, ray.Origin + ray.Direction * distance)
end

local function aimAt(view: View, screen: Vector3)
	local cue = cueBall(view)
	local x, y = tablePoint(view, screen)
	if not cue or not x or not y then
		return
	end
	local dx, dy = x - cue.x, y - cue.y
	if dx * dx + dy * dy > view.geometry.ballRadius ^ 2 then
		aim.angle = math.atan2(dy, dx)
	end
end

local function setPower(power: number)
	aim.power = power
	hud.setPower(power)
end

local function shoot(power: number)
	setPower(0)
	if power < Controls.MinPower or not aimingView() then
		return
	end
	Remotes.Event("Shot"):FireServer({
		angle = aim.angle,
		power = power,
		spinX = aim.spinX,
		spinY = aim.spinY,
		elevation = aim.elevation,
	})
	waitingSince = os.clock()
	aim.spinX, aim.spinY, aim.elevation = 0, 0, 0
	hud.setSpin(0, 0)
	hud.setElevation(0)
end

local function onInputBegan(input: InputObject, processed: boolean)
	local view = aimingView()
	if processed or not view then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch then
		aimTouch = input
		aimAt(view, input.Position)
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local x, y = tablePoint(view, input.Position)
		if x and y then
			pullStart = { x = x, y = y }
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		pullStart = nil
		setPower(0)
	end
end

local function onInputChanged(input: InputObject, processed: boolean)
	local view = aimingView()
	if not view then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch and input == aimTouch then
		aimAt(view, input.Position)
	elseif input.UserInputType == Enum.UserInputType.MouseMovement then
		local start = pullStart
		if start then
			local x, y = tablePoint(view, input.Position)
			if x and y then
				local pull = (start.x - x) * math.cos(aim.angle) + (start.y - y) * math.sin(aim.angle)
				setPower(math.clamp(pull / Controls.MaxPullMeters, 0, 1))
			end
		elseif not processed then
			aimAt(view, input.Position)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		aim.angle += input.Position.Z * Controls.WheelRadians
	end
end

local function onInputEnded(input: InputObject)
	if input == aimTouch then
		aimTouch = nil
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and pullStart then
		pullStart = nil
		shoot(aim.power)
	end
end

local function update(dt: number)
	if waitingSince and os.clock() - waitingSince > Controls.ShotResultTimeout then
		waitingSince = nil
	end
	local view = aimingView()
	hud.setAimEnabled(view ~= nil)
	visuals.Parent = if view then Workspace else nil
	if not view then
		return
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		aim.angle += Controls.KeyRadiansPerSecond * dt
	elseif UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		aim.angle -= Controls.KeyRadiansPerSecond * dt
	end
	local cue = cueBall(view)
	if cue then
		drawAim(view, cue)
	end
end

local AimController = {}

function AimController.Init()
	visuals = Instance.new("Folder")
	visuals.Name = "AimVisuals"
	guideMain = visualPart("GuideMain", Enum.PartType.Block, 0.15)
	guideTarget = visualPart("GuideTarget", Enum.PartType.Block, 0.15)
	guideCue = visualPart("GuideCue", Enum.PartType.Block, 0.15)
	ghost = visualPart("Ghost", Enum.PartType.Ball, 0.6)
	ghost.Size = Vector3.one * TableSpace.studs(2 * Physics.BallRadius)
	cueStick = visualPart("Cue", Enum.PartType.Cylinder, 0)
	cueStick.Material = Enum.Material.Wood
	cueStick.Color = Color3.fromRGB(160, 110, 60)

	hud = TableHud.new({
		onPower = setPower,
		onRelease = shoot,
		onFine = function(delta)
			aim.angle += delta
		end,
		onSpin = function(spinX, spinY)
			aim.spinX, aim.spinY = spinX, spinY
		end,
		onElevation = function(radians)
			aim.elevation = radians
		end,
		onLeave = function()
			Remotes.Event("LeaveTable"):FireServer()
		end,
		onRerack = function()
			Remotes.Event("Rerack"):FireServer()
		end,
	})
end

function AimController.Start()
	TableViewController.SeatChanged:Connect(function(tableId)
		hud.setVisible(tableId ~= nil)
		aim.angle, aim.power = 0, 0
		waitingSince, pullStart, aimTouch = nil, nil, nil
	end)
	TableViewController.ShotStarted:Connect(function(tableId)
		local view = TableViewController.seatedView()
		if view and view.id == tableId then
			waitingSince = nil
		end
	end)
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
	RunService.RenderStepped:Connect(update)
end

return AimController
