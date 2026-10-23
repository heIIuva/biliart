--!strict
-- Draws tables on this client: balls as local anchored parts, the top-down table camera while
-- seated, and playback of server trajectories (interpolated, with event sounds).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Controls = require(Shared.Config.Controls)
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)
local TableGeometry = require(Shared.Pool.TableGeometry)
local TableSpace = require(Shared.World.TableSpace)
local Text = require(Shared.Util.Text)
local TrajectoryCodec = require(Shared.Pool.TrajectoryCodec)
local Sfx = require(script.Parent.Parent.Util.Sfx)

local Kind = PoolPhysics.EventKind
local STRIDE = PoolPhysics.FRAME_STRIDE
local DEFAULT_FOV = 70
local TABLE_BORDER_METERS = 0.17 -- cushion + frame around the playing field

type Track = { times: { number }, cframes: { CFrame }, cursor: number }

type Playback = {
	t: number,
	timeScale: number, -- HypeController slows the decisive moment down
	duration: number,
	frameDt: number,
	tracks: { [number]: Track },
	events: { PoolPhysics.Event },
	nextEvent: number,
	final: { PoolPhysics.BallState },
	hype: Remotes.HypePayload?,
}

-- The last shot played at a table, kept for the replay (clip mode).
export type LastShot = {
	before: { PoolPhysics.BallState },
	decoded: TrajectoryCodec.Decoded,
	final: { PoolPhysics.BallState },
	hype: Remotes.HypePayload?,
}

export type View = {
	id: string,
	geometry: TableGeometry.Geometry,
	surface: CFrame,
	balls: { PoolPhysics.BallState },
	parts: { [number]: BasePart },
	folder: Folder,
	playback: Playback?,
	lastShot: LastShot?,
}

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
local WHITE = Color3.fromRGB(245, 243, 230)
local CUE_SPOT = Color3.fromRGB(200, 30, 30)

local player = Players.LocalPlayer
local views: { [string]: View } = {}
local seatedId: string? = nil

local TableViewController = {
	SeatChanged = Signal.new(), -- (tableId: string?)
	PlaybackFinished = Signal.new(), -- (tableId: string, hype: Remotes.HypePayload?)
	ShotStarted = Signal.new(), -- (tableId: string)
	StateChanged = Signal.new(), -- (tableId: string): balls are at rest in view.balls
}

-- Classic Weld with an explicit offset: unlike WeldConstraint it does not depend on where the
-- parts are when the weld activates, so the ball can be placed before it enters the world.
local function attach(ball: BasePart, child: BasePart, offset: CFrame)
	child.Anchored = false
	child.CanCollide = false
	child.CanQuery = false
	child.CanTouch = false
	child.Massless = true
	child.Material = Enum.Material.SmoothPlastic
	local weld = Instance.new("Weld")
	weld.Part0 = ball
	weld.Part1 = child
	weld.C0 = offset
	weld.Parent = child
	child.Parent = ball
end

-- Fallback ball with a visible mark (stripe band or spot) so rolling and spin read on screen.
local function makePrimitiveBall(id: number, diameter: number): BasePart
	local secondCue = id == 16 -- speed pool: player 2's cue ball
	local stripe = id >= 9 and not secondCue
	local ball = Instance.new("Part")
	ball.Name = `Ball{id}`
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * diameter
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = if stripe or secondCue then WHITE else BALL_COLORS[id]
	if stripe then
		local band = Instance.new("Part")
		band.Shape = Enum.PartType.Cylinder
		band.Size = Vector3.new(diameter * 0.55, diameter * 1.01, diameter * 1.01)
		band.Color = BALL_COLORS[id - 8]
		attach(ball, band, CFrame.identity)
	else
		local spot = Instance.new("Part")
		spot.Shape = Enum.PartType.Ball
		spot.Size = Vector3.one * diameter * 0.3
		spot.Color = if id == 0 then CUE_SPOT elseif secondCue then Color3.fromRGB(30, 80, 220) else WHITE
		attach(ball, spot, CFrame.new(0, diameter * 0.4, 0))
	end
	return ball
end

-- MeshId cannot be set at runtime, so every textured ball is a clone of one template mesh
-- (ReplicatedStorage.Assets.BallMesh, imported from assets/balls/pool_ball.obj in Studio).
local function findBallTemplate(): MeshPart?
	local folder = ReplicatedStorage:FindFirstChild("Assets")
	local template = folder and folder:FindFirstChild("BallMesh")
	return if template and template:IsA("MeshPart") then template else nil
end

local ballTemplate = findBallTemplate()

-- Textured mesh ball. Mesh pole is local X, number discs at local +Y/-Y, glyph "up" = local -Z,
-- so with identity rotation the number faces the top-down table camera upright.
local function makeBall(id: number, diameter: number): BasePart
	local texture = Assets.BallTextures[id]
	if not ballTemplate or not texture or texture == 0 then
		return makePrimitiveBall(id, diameter)
	end
	local ball = ballTemplate:Clone()
	ball.Name = `Ball{id}`
	ball.Size = Vector3.one * diameter
	ball.TextureID = `rbxassetid://{texture}`
	ball.Color = Color3.new(1, 1, 1)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Reflectance = 0.05
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = true
	return ball
end

local function applyBalls(view: View)
	local R = view.geometry.ballRadius
	local present: { [number]: boolean } = {}
	for _, b in view.balls do
		present[b.id] = true
	end
	for id, part in view.parts do
		if not present[id] then
			part.Parent = nil -- a new layout (trick, sandbox) without this ball
		end
	end
	for _, b in view.balls do
		local part = view.parts[b.id]
		if not part then
			part = makeBall(b.id, TableSpace.studs(2 * R))
			view.parts[b.id] = part
		end
		if b.status == "Stationary" then
			part.CFrame = TableSpace.ballCFrame(view.surface, b.x, b.y, R, b.qx or 0, b.qy or 0, b.qz or 0, b.qw or 1)
			part.Parent = view.folder
		else
			part.Parent = nil
		end
	end
end

local function finish(view: View)
	local playback = view.playback
	if not playback then
		return
	end
	view.playback = nil
	view.balls = playback.final
	applyBalls(view)
	TableViewController.PlaybackFinished:Fire(view.id, playback.hype)
	TableViewController.StateChanged:Fire(view.id)
end

local function buildPlayback(
	view: View,
	decoded: TrajectoryCodec.Decoded,
	final: { PoolPhysics.BallState },
	hype: Remotes.HypePayload?
): Playback
	local frameDt = 1 / decoded.recordHz
	local tracks: { [number]: Track } = {}
	for _, frame in decoded.frames do
		local data = frame.data
		for i = 1, #data, STRIDE do
			local id = data[i]
			local track = tracks[id]
			if not track then
				local created: Track = { times = {}, cframes = {}, cursor = 1 }
				-- Hold the ball where it rests until one frame before it was first seen moving.
				local part = view.parts[id]
				if part and frame.t > 0 then
					table.insert(created.times, frame.t - frameDt)
					table.insert(created.cframes, part.CFrame)
				end
				tracks[id] = created
				track = created
			end
			table.insert(track.times, frame.t)
			table.insert(
				track.cframes,
				TableSpace.ballCFrame(
					view.surface,
					data[i + 1],
					data[i + 2],
					data[i + 3],
					data[i + 4],
					data[i + 5],
					data[i + 6],
					data[i + 7]
				)
			)
		end
	end
	local last = decoded.frames[#decoded.frames]
	return {
		t = 0,
		timeScale = 1,
		hype = hype,
		duration = if last then last.t else 0,
		frameDt = frameDt,
		tracks = tracks,
		events = decoded.events,
		nextEvent = 1,
		final = final,
	}
end

local function playEvent(view: View, event: PoolPhysics.Event)
	local volume = math.clamp(event.speed / 4, 0.05, 1)
	local kind = event.kind
	if kind == Kind.CueStrike then
		Sfx.play("CueStrike", volume)
	elseif kind == Kind.BallBall then
		Sfx.play("BallHit", volume)
	elseif kind == Kind.BallCushion then
		Sfx.play("CushionHit", volume)
	elseif kind == Kind.BallJaw then
		Sfx.play("JawHit", volume)
	elseif kind == Kind.Landed then
		Sfx.play("Land", volume)
	elseif kind == Kind.Pocketed or kind == Kind.OffTable then
		if kind == Kind.Pocketed then
			Sfx.play("Pocket", volume)
		end
		local part = view.parts[event.a]
		if part then
			part.Parent = nil
		end
	end
end

local function step(view: View, playback: Playback, dt: number)
	playback.t += dt * playback.timeScale
	local t = playback.t
	for id, track in playback.tracks do
		local part = view.parts[id]
		local times, cframes = track.times, track.cframes
		if not part or t < times[1] then
			continue
		end
		local c = track.cursor
		while c < #times and times[c + 1] <= t do
			c += 1
		end
		track.cursor = c
		if c >= #times then
			part.CFrame = cframes[c]
		else
			-- Gaps mean the ball rested in between: start moving one frame before the next sample.
			local nextT = times[c + 1]
			local start = math.max(times[c], nextT - playback.frameDt)
			local alpha = if t <= start then 0 else (t - start) / (nextT - start)
			part.CFrame = cframes[c]:Lerp(cframes[c + 1], alpha)
		end
	end
	local events = playback.events
	while playback.nextEvent <= #events and events[playback.nextEvent].t <= t do
		playEvent(view, events[playback.nextEvent])
		playback.nextEvent += 1
	end
	if t >= playback.duration then
		finish(view)
	end
end

local function cameraTarget(view: View): CFrame
	local camera = Workspace.CurrentCamera
	local viewport = camera.ViewportSize
	local aspect = viewport.X / math.max(viewport.Y, 1)
	local tanHalf = math.tan(math.rad(Controls.CameraFov) / 2)
	local g = view.geometry
	local width = TableSpace.studs(2 * (g.halfLength + TABLE_BORDER_METERS)) * Controls.CameraWidthPadding
	local height = TableSpace.studs(2 * (g.halfWidth + TABLE_BORDER_METERS)) * Controls.CameraHeightPadding
	local distance = math.max(height / (2 * tanHalf), width / (2 * tanHalf * aspect))
	local center = view.surface.Position
	-- Long side across the screen, sim +Y (surface -Z) up.
	return CFrame.lookAt(center + view.surface.UpVector * distance, center, -view.surface.ZVector)
end

-- The seated character is anchored by the server; this only hides the mobile thumbstick/jump.
local function setTouchControls(enabled: boolean)
	GuiService.TouchControlsEnabled = enabled
end

local function enterTable(view: View)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local info = TweenInfo.new(Controls.CameraTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(camera, info, { CFrame = cameraTarget(view), FieldOfView = Controls.CameraFov }):Play()
	ProximityPromptService.Enabled = false
	setTouchControls(false)
end

local function leaveTable()
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local head = character and character:FindFirstChild("Head") :: BasePart?
	ProximityPromptService.Enabled = true
	setTouchControls(true)
	if not head then
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = DEFAULT_FOV
		return
	end
	local behind = head.CFrame * CFrame.new(0, 2, 10)
	local info = TweenInfo.new(Controls.CameraTweenSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(camera, info, {
		CFrame = CFrame.lookAt(behind.Position, head.Position),
		FieldOfView = DEFAULT_FOV,
	})
	tween.Completed:Once(function()
		if seatedId == nil then
			camera.CameraType = Enum.CameraType.Custom
		end
	end)
	tween:Play()
end

local function onTableState(snapshot: Remotes.TableSnapshot)
	local view = views[snapshot.tableId]
	if not view then
		local folder = Instance.new("Folder")
		folder.Name = `Balls_{snapshot.tableId}`
		folder.Parent = Workspace
		view = {
			id = snapshot.tableId,
			geometry = TableGeometry.get(snapshot.variant :: TableGeometry.Variant),
			surface = snapshot.surface,
			balls = snapshot.balls,
			parts = {},
			folder = folder,
			playback = nil,
			lastShot = nil,
		}
		views[snapshot.tableId] = view
	end
	view.playback = nil
	view.surface = snapshot.surface
	view.balls = snapshot.balls
	applyBalls(view)
	TableViewController.StateChanged:Fire(view.id)
end

local function onShotResult(message: Remotes.ShotResultPayload)
	local view = views[message.tableId]
	if not view then
		return
	end
	finish(view)
	local decoded = TrajectoryCodec.decode(message.trajectory)
	view.lastShot = { before = table.clone(view.balls), decoded = decoded, final = message.balls, hype = message.hype }
	view.playback = buildPlayback(view, decoded, message.balls, message.hype)
	TableViewController.ShotStarted:Fire(view.id)
end

local function onSeatChanged(tableId: string?)
	seatedId = tableId
	local view = if tableId then views[tableId] else nil
	if view then
		enterTable(view)
	else
		leaveTable()
	end
	TableViewController.SeatChanged:Fire(tableId)
end

-- Moves a resting ball locally (ball in hand preview); the server gets the spot with the shot.
function TableViewController.moveBall(view: View, id: number, x: number, y: number)
	for _, b in view.balls do
		if b.id == id then
			b.x, b.y = x, y
			local part = view.parts[id]
			if part then
				local R = view.geometry.ballRadius
				part.CFrame = TableSpace.ballCFrame(view.surface, x, y, R, b.qx or 0, b.qy or 0, b.qz or 0, b.qw or 1)
			end
		end
	end
end

-- Plays the last shot again from its starting position (no splash). False if there is nothing
-- to replay or a live shot is playing.
function TableViewController.replay(view: View): boolean
	local last = view.lastShot
	if not last or view.playback then
		return false
	end
	view.balls = table.clone(last.before)
	applyBalls(view)
	view.playback = buildPlayback(view, last.decoded, last.final, nil)
	return true
end

-- Puts the camera back to the seated table view (after the clip took it over).
function TableViewController.resetCamera()
	local view = TableViewController.seatedView()
	if view then
		Workspace.CurrentCamera.CFrame = cameraTarget(view)
		Workspace.CurrentCamera.FieldOfView = Controls.CameraFov
	end
end

-- Chaos: gold outline on the golden balls.
function TableViewController.setHighlights(view: View, ids: { number })
	for id, part in view.parts do
		local existing = part:FindFirstChild("Golden")
		local wanted = table.find(ids, id) ~= nil
		if wanted and not existing then
			local highlight = Instance.new("Highlight")
			highlight.Name = "Golden"
			highlight.FillColor = Color3.fromRGB(255, 200, 40)
			highlight.OutlineColor = Color3.fromRGB(255, 230, 120)
			highlight.FillTransparency = 0.4
			highlight.Parent = part
		elseif not wanted and existing then
			existing:Destroy()
		end
	end
end

-- Chaos: a fog layer over the table for the player who got fogged.
local fogPart: Part? = nil
function TableViewController.setFog(view: View, on: boolean)
	if on and not fogPart then
		local fog = Instance.new("Part")
		fog.Name = "Fog"
		fog.Anchored = true
		fog.CanCollide = false
		fog.CanQuery = false
		fog.Material = Enum.Material.SmoothPlastic
		fog.Color = Color3.fromRGB(230, 230, 235)
		fog.Transparency = 0.25
		local g = view.geometry
		fog.Size = Vector3.new(TableSpace.studs(2 * g.halfLength) * 0.6, 0.05, TableSpace.studs(2 * g.halfWidth))
		fog.CFrame = view.surface * CFrame.new(TableSpace.studs(g.halfLength * 0.35), TableSpace.studs(0.12), 0)
		fog.Parent = Workspace
		fogPart = fog
	elseif not on and fogPart then
		fogPart:Destroy()
		fogPart = nil
	end
end

-- Sandbox: switch between the fixed top view and a free orbit camera around the table.
local orbitAnchor: Part? = nil
function TableViewController.toggleFreeCamera()
	local view = TableViewController.seatedView()
	local camera = Workspace.CurrentCamera
	if not view then
		return
	end
	if orbitAnchor then
		orbitAnchor:Destroy()
		orbitAnchor = nil
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cameraTarget(view)
		camera.FieldOfView = Controls.CameraFov
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "OrbitAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = view.surface
	anchor.Parent = Workspace
	orbitAnchor = anchor
	camera.FieldOfView = 50
	camera.CameraSubject = anchor
	camera.CameraType = Enum.CameraType.Custom
end

-- Speed pool: sounds and pocket effects for live events.
function TableViewController.playEvents(view: View, events: { PoolPhysics.Event })
	for _, event in events do
		playEvent(view, event)
	end
end

-- Speed pool: makes sure every ball in the list has a part (e.g. the second cue ball).
function TableViewController.ensureBalls(view: View, balls: { PoolPhysics.BallState })
	view.balls = balls
	applyBalls(view)
end

function TableViewController.view(tableId: string): View?
	return views[tableId]
end

function TableViewController.seatedView(): View?
	return if seatedId then views[seatedId] else nil
end

function TableViewController.Start()
	Remotes.Event("TableState").OnClientEvent:Connect(onTableState)
	Remotes.Event("ShotResult").OnClientEvent:Connect(onShotResult)
	Remotes.Event("SeatChanged").OnClientEvent:Connect(onSeatChanged)

	ProximityPromptService.PromptShown:Connect(function(prompt)
		local action, object = prompt:GetAttribute("ActionKey"), prompt:GetAttribute("ObjectKey")
		if type(action) == "string" then
			prompt.ActionText = Text.get(action)
		end
		if type(object) == "string" then
			prompt.ObjectText = Text.get(object)
		end
	end)

	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local view = TableViewController.seatedView()
		if view then
			Workspace.CurrentCamera.CFrame = cameraTarget(view)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		for _, view in views do
			local playback = view.playback
			if playback then
				step(view, playback, dt)
			end
		end
	end)
end

return TableViewController
