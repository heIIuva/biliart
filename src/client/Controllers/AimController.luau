--!strict
-- Aiming and shooting at the seated table, on the local player's turn.
-- Touch: the finger on the table points the cue; power bar on the left, fine wheel on the right.
-- Mouse: the cursor points the cue; hold LMB and pull back for power, release to shoot
-- (RMB cancels); wheel / arrow keys fine-tune.
-- Ball in hand: press on the cue ball and drag it. Shooting the 8: tap a pocket to call it.
-- Only the intent goes to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AimPredictor = require(Shared.Pool.AimPredictor)
local Controls = require(Shared.Config.Controls)
local Physics = require(Shared.Config.Physics)
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local PoolRules = require(Shared.Pool.PoolRules)
local Remotes = require(Shared.Net.Remotes)
local TableSpace = require(Shared.World.TableSpace)
local TableHud = require(script.Parent.Parent.UI.TableHud)
local MatchController = require(script.Parent.MatchController)
local TableViewController = require(script.Parent.TableViewController)

type View = TableViewController.View

local LINE_THICKNESS = 0.006 -- meters
local CUE_DIAMETER = 0.025
local GRAB_RADIUS_TOUCH = 0.08 -- how close to the cue ball a press starts dragging it (meters)
local GRAB_RADIUS_MOUSE = 0.04
local POCKET_PICK_RADIUS = 0.09
local POCKET_COLOR = Color3.fromRGB(255, 255, 255)
local POCKET_CALLED_COLOR = Color3.fromRGB(240, 190, 60)

local aim = { angle = 0, power = 0, spinX = 0, spinY = 0, elevation = 0 }
local waitingSince: number? = nil -- shot sent, result not arrived yet
local aimTouch: InputObject? = nil
local pullStart: { x: number, y: number }? = nil
local dragInput: InputObject? = nil -- touch or mouse press moving the cue ball (ball in hand)
local dragId = 0 -- ball being dragged (sandbox: any ball)
local calledPocket: number? = nil
local shownTurn = 0 -- turnEndsAt of the turn the aim state belongs to
local hud: TableHud.Hud
local visuals: Folder
local guideMain: Part
local guideTarget: Part
local guideCue: Part
local ghost: Part
local cueStick: Part
local pocketMarkers: { Part } = {}

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
	if view and view.playback == nil and waitingSince == nil and MatchController.canShoot() and cueBall(view) then
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

-- Aim guide length multiplier of the local player's cue in this match.
local function aimScale(): number
	local match = MatchController.current()
	if match then
		for _, p in match.players do
			if not p.isBot and p.userId == Players.LocalPlayer.UserId then
				return p.aim
			end
		end
	end
	return 1
end

local function drawAim(view: View, cue: PoolPhysics.BallState)
	local R = view.geometry.ballRadius
	local scale = aimScale()
	local surface = view.surface
	local prediction = AimPredictor.predict(view.geometry, view.balls, aim.angle)
	local from = TableSpace.toWorld(surface, cue.x, cue.y, R)
	local contact = TableSpace.toWorld(surface, prediction.ghostX, prediction.ghostY, R)

	setLine(guideMain, from, contact)
	ghost.Transparency = if prediction.kind == "None" then 1 else 0.6
	ghost.Position = contact

	local targetLength = if prediction.kind == "Ball" then Controls.GuideObjectMeters * scale else 0
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
			prediction.ghostX + prediction.cueDirX * Controls.GuideCueMeters * scale,
			prediction.ghostY + prediction.cueDirY * Controls.GuideCueMeters * scale,
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
	local view = aimingView()
	local match = MatchController.current()
	if power < Controls.MinPower or not view or not match then
		return
	end
	if match.mustCall and not calledPocket then
		MatchController.flash("HINT_CALL_POCKET")
		return
	end
	local cue = cueBall(view) :: PoolPhysics.BallState
	Remotes.Event("Shot"):FireServer({
		angle = aim.angle,
		power = power,
		spinX = aim.spinX,
		spinY = aim.spinY,
		elevation = aim.elevation,
		calledPocket = if match.mustCall then calledPocket else nil,
		cueBallPos = if match.ballInHand then { x = cue.x, y = cue.y } else nil,
		superShot = MatchController.superShot(),
	})
	MatchController.shotSent()
	waitingSince = os.clock()
	aim.spinX, aim.spinY, aim.elevation = 0, 0, 0
	hud.setSpin(0, 0)
	hud.setElevation(0)
end

-- Ball in hand / sandbox: move the ball to a legal spot under the pointer (keeps the last legal one).
local function dragCue(view: View, screen: Vector3)
	local match = MatchController.current()
	local x, y = tablePoint(view, screen)
	if not match or not x or not y then
		return
	end
	if dragId == 0 and PoolRules.canPlaceCue(view.geometry, view.balls, x, y, match.kitchenOnly) then
		TableViewController.moveBall(view, 0, x, y)
	elseif dragId ~= 0 then
		local R = view.geometry.ballRadius
		local ok = math.abs(x) <= view.geometry.halfLength - R and math.abs(y) <= view.geometry.halfWidth - R
		for _, b in view.balls do
			if ok and b.id ~= dragId and b.status == "Stationary" and (b.x - x) ^ 2 + (b.y - y) ^ 2 < (2 * R) ^ 2 then
				ok = false
			end
		end
		if ok then
			TableViewController.moveBall(view, dragId, x, y)
		end
	end
end

-- Handles presses that pick a pocket or grab the cue ball; true if the press was used.
local function pressSpecial(view: View, input: InputObject): boolean
	local match = MatchController.current()
	local x, y = tablePoint(view, input.Position)
	if not match or not x or not y then
		return false
	end
	if match.mustCall then
		for _, pocket in view.geometry.pockets do
			if (pocket.x - x) ^ 2 + (pocket.y - y) ^ 2 < POCKET_PICK_RADIUS ^ 2 then
				calledPocket = pocket.id
				return true
			end
		end
	end
	local grab = if input.UserInputType == Enum.UserInputType.Touch then GRAB_RADIUS_TOUCH else GRAB_RADIUS_MOUSE
	if match.mode == "Sandbox" then
		for _, b in view.balls do
			if b.status == "Stationary" and (b.x - x) ^ 2 + (b.y - y) ^ 2 < grab ^ 2 then
				dragInput, dragId = input, b.id
				return true
			end
		end
		return false
	end
	local cue = cueBall(view)
	if match.ballInHand and cue and (cue.x - x) ^ 2 + (cue.y - y) ^ 2 < grab ^ 2 then
		dragInput, dragId = input, 0
		return true
	end
	return false
end

local function onInputBegan(input: InputObject, processed: boolean)
	local view = aimingView()
	if processed or not view then
		return
	end
	local press = input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
	if press and pressSpecial(view, input) then
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
	local drag = dragInput
	if drag then
		local same = input == drag
			or (
				drag.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if same then
			dragCue(view, input.Position)
			return
		end
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
	local drag = dragInput
	if
		drag
		and (
			input == drag
			or (
				drag.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1
			)
		)
	then
		dragInput = nil
		local match = MatchController.current()
		local view = TableViewController.seatedView()
		if match and view and match.mode == "Sandbox" then
			for _, b in view.balls do
				if b.id == dragId then
					Remotes.Event("Sandbox"):FireServer({ action = "place", id = dragId, x = b.x, y = b.y })
				end
			end
		end
	elseif input == aimTouch then
		aimTouch = nil
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 and pullStart then
		pullStart = nil
		shoot(aim.power)
	end
end

local function drawPockets(view: View?, match: Remotes.MatchSnapshot?)
	local show = view ~= nil and match ~= nil and match.mustCall
	for i, marker in pocketMarkers do
		local pocket = if view then view.geometry.pockets[i] else nil
		if show and view and pocket then
			marker.Transparency = 0.3
			marker.Color = if calledPocket == pocket.id then POCKET_CALLED_COLOR else POCKET_COLOR
			marker.CFrame = CFrame.new(TableSpace.toWorld(view.surface, pocket.x, pocket.y, 0.002))
				* view.surface.Rotation
				* CFrame.Angles(0, 0, math.pi / 2)
		else
			marker.Transparency = 1
		end
	end
end

local function update(dt: number)
	if waitingSince and os.clock() - waitingSince > Controls.ShotResultTimeout then
		waitingSince = nil
	end
	local match = MatchController.current()
	local turn = if match then match.turnEndsAt else 0
	if turn ~= shownTurn then
		shownTurn = turn
		calledPocket, dragInput, pullStart = nil, nil, nil
		setPower(0)
	end
	local view = aimingView()
	drawPockets(view, match)
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
	for i = 1, 6 do
		local marker = visualPart(`Pocket{i}`, Enum.PartType.Cylinder, 1)
		local size = TableSpace.studs(0.09)
		marker.Size = Vector3.new(TableSpace.studs(0.004), size, size)
		pocketMarkers[i] = marker
	end

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
	})
end

function AimController.Start()
	TableViewController.SeatChanged:Connect(function(tableId)
		hud.setVisible(tableId ~= nil)
		aim.angle, aim.power = 0, 0
		waitingSince, pullStart, aimTouch, dragInput, calledPocket = nil, nil, nil, nil, nil
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
