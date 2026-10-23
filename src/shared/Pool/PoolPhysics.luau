--!strict
--!native
-- Deterministic pool simulation. Pure Luau: no Roblox API, no math.random.
--
-- Model: each ball slides until cloth friction turns it into pure rolling (this is what makes
-- follow/draw/stun and masse work), rolling resistance then stops it; spin around the vertical
-- axis decays separately. Ball-ball contacts are frictionless (spins pass through unchanged),
-- cushions add tangential friction so side spin bends the rebound.
--
-- Time stepping: fixed steps of 1/SimHz. Inside a step every ball moves along a straight line at
-- its mean step velocity; the earliest contact in the step (ball-ball quadratic, cushion line,
-- knuckle, pocket capture, landing) is found exactly, the simulation advances to it, resolves it
-- and searches again. Nothing can tunnel regardless of speed.

local Physics = require("../Config/Physics")
local TableGeometry = require("./TableGeometry")

export type Status = "Stationary" | "Sliding" | "Rolling" | "Spinning" | "Airborne" | "Pocketed" | "OffTable"

-- Between shots a ball is Stationary, Pocketed or OffTable. Orientation is optional (identity).
export type BallState = {
	id: number, -- 0 = cue ball, 1..15 object balls
	x: number,
	y: number,
	status: Status,
	qx: number?,
	qy: number?,
	qz: number?,
	qw: number?,
}

export type TableState = {
	geometry: TableGeometry.Geometry,
	balls: { BallState },
}

export type ShotParams = {
	angle: number, -- radians, 0 = +X
	power: number, -- 0..1
	spinX: number, -- tip offset, fraction of radius: +X = right english
	spinY: number, -- +Y = top (follow), -Y = bottom (draw)
	elevation: number, -- cue elevation, radians
}

-- Event fields by kind:
--   CueStrike a = 0                     BallBall    a, b = ball ids
--   BallCushion a = ball, b = cushionId  BallJaw / Pocketed / Rattle  a = ball, b = pocketId
--   Airborne / Landed / OffTable  a = ball
-- speed: impact speed along the contact normal (m/s); for CueStrike the cue ball speed.
export type Event = {
	t: number,
	kind: number,
	a: number,
	b: number,
	speed: number,
}

-- A recorded frame lists only balls that moved: FRAME_STRIDE numbers per ball
-- (id, x, y, z, qx, qy, qz, qw). z is the height of the ball center above the cloth plane.
export type Frame = {
	t: number,
	data: { number },
}

export type Params = typeof(Physics)

export type SimOptions = {
	record: boolean?, -- default true; the bot turns it off
	maxSeconds: number?,
	params: Params?,
}

-- A cue ball flight from takeoff to touchdown (for "jumped over a ball" checks).
export type Jump = { x0: number, y0: number, x1: number, y1: number }

export type SimResult = {
	finalState: { BallState },
	events: { Event },
	frames: { Frame },
	recordHz: number,
	duration: number,
	travel: { [number]: number }, -- distance each ball rolled/slid/flew (meters)
	cueCurve: number, -- max sideways drift of the cue ball from its aim line before its first contact (masse)
	cueJumps: { Jump },
}

type Ball = {
	id: number,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	wx: number,
	wy: number,
	wz: number,
	status: Status,
	-- Constant within the current step:
	ax: number, -- linear acceleration
	ay: number,
	awx: number, -- angular acceleration while sliding
	awy: number,
	sx: number, -- mean velocity used to move the ball for the rest of the step
	sy: number,
	qx: number,
	qy: number,
	qz: number,
	qw: number,
	dirty: boolean, -- changed state since the last recorded frame
	travel: number,
}

local EventKind = {
	CueStrike = 1,
	BallBall = 2,
	BallCushion = 3,
	BallJaw = 4,
	Pocketed = 5,
	Airborne = 6,
	Landed = 7,
	Rattle = 8,
	OffTable = 9,
}

local FRAME_STRIDE = 8
local SPIN_EPSILON = 0.05 -- rad/s
local PENETRATION_TOLERANCE = 1e-4

-- Kinds of the earliest contact found in a step.
local HIT_NONE, HIT_BALL, HIT_SEGMENT, HIT_ENDPOINT, HIT_POCKET, HIT_LAND = 0, 1, 2, 3, 4, 5

local sqrt, abs = math.sqrt, math.abs

local function isMoving(status: Status): boolean
	return status == "Sliding" or status == "Rolling" or status == "Airborne"
end

local function isOnTable(status: Status): boolean
	return status ~= "Pocketed" and status ~= "OffTable"
end

local PoolPhysics = {}

PoolPhysics.EventKind = EventKind
PoolPhysics.FRAME_STRIDE = FRAME_STRIDE

-- The simulation state and its step function. simulateShot runs one shot on it; newWorld exposes
-- it for continuous play (speed pool), where several cue balls can be struck at any time.
local function makeWorld(state: TableState, P: Params)
	local geometry = state.geometry

	local R = geometry.ballRadius
	local g = P.Gravity
	local hl, hw = geometry.halfLength, geometry.halfWidth
	local safeX, safeY = hl - R, hw - R -- inside this box no cushion or pocket can be touched
	local segments, pockets = geometry.segments, geometry.pockets

	local slideDecel = P.SlideFriction * g
	local slideSpinAccel = 2.5 * P.SlideFriction * g / R
	local slipDecay = 3.5 * P.SlideFriction * g -- how fast the contact-point slip vanishes
	local rollDecel = P.RollFriction * g
	local spinDecel = 2.5 * P.SpinFriction * g / (R * R)
	local ballE, cushionE = P.BallRestitution, P.CushionRestitution

	local dt = 1 / P.SimHz

	local balls: { Ball } = {}
	local cue: Ball? = nil
	for _, s in state.balls do
		local ball: Ball = {
			id = s.id,
			x = s.x,
			y = s.y,
			z = R,
			vx = 0,
			vy = 0,
			vz = 0,
			wx = 0,
			wy = 0,
			wz = 0,
			status = if isOnTable(s.status) then "Stationary" else s.status,
			ax = 0,
			ay = 0,
			awx = 0,
			awy = 0,
			sx = 0,
			sy = 0,
			qx = s.qx or 0,
			qy = s.qy or 0,
			qz = s.qz or 0,
			qw = s.qw or 1,
			dirty = false,
			travel = 0,
		}
		table.insert(balls, ball)
		if s.id == 0 then
			cue = ball
		end
	end
	local ballCount = #balls

	local events: { Event } = {}
	local frames: { Frame } = {}
	local t = 0
	-- Cue ball path stats for the shot report.
	local aimX, aimY, aimDX, aimDY = 0, 0, 1, 0
	local cueCurve = 0
	local cueTouched = false -- first ball/cushion contact ends the curve measurement
	local cueJumps: { Jump } = {}
	local takeoffX, takeoffY = 0, 0

	local function emit(kind: number, a: number, b: number, speed: number, at: number)
		table.insert(events, { t = at, kind = kind, a = a, b = b, speed = speed })
	end

	-- Strike: impulse along the (elevated) cue through the tip contact point.
	local function strike(ball: Ball, shot: ShotParams)
		local angle = shot.angle
		local power = math.clamp(shot.power, 0, 1)
		local elevation = math.clamp(shot.elevation, 0, P.MaxElevation)
		local spinX, spinY = shot.spinX, shot.spinY
		local offset = sqrt(spinX * spinX + spinY * spinY)
		if offset > P.MaxTipOffset then
			spinX, spinY = spinX * P.MaxTipOffset / offset, spinY * P.MaxTipOffset / offset
		end
		local speed = power * P.MaxCueSpeed
		local fx, fy = math.cos(angle), math.sin(angle)
		local lx, ly = -fy, fx -- left of the shot direction
		local ce, se = math.cos(elevation), math.sin(elevation)
		local k = 2.5 * speed / R
		ball.vx, ball.vy = speed * ce * fx, speed * ce * fy
		ball.wx = k * (spinX * se * fx + spinY * lx)
		ball.wy = k * (spinX * se * fy + spinY * ly)
		ball.wz = k * spinX * ce
		ball.status = "Sliding"
		emit(EventKind.CueStrike, ball.id, 0, speed, t)
		if ball.id == 0 then
			aimX, aimY, aimDX, aimDY = ball.x, ball.y, fx, fy
			cueTouched = false
		end
		local vz = P.JumpRestitution * speed * se
		if vz >= P.MinJumpSpeed then
			ball.vz = vz
			ball.status = "Airborne"
			emit(EventKind.Airborne, ball.id, 0, vz, t)
			if ball.id == 0 then
				takeoffX, takeoffY = ball.x, ball.y
			end
		end
	end

	-- Sets the step-constant accelerations and mean velocity for the remaining step time h.
	local function prepare(b: Ball, h: number)
		b.ax, b.ay, b.awx, b.awy = 0, 0, 0, 0
		local status: Status = b.status
		if status == "Sliding" then
			local ux, uy = b.vx - R * b.wy, b.vy + R * b.wx
			local u = sqrt(ux * ux + uy * uy)
			if u <= slipDecay * h then
				status = "Rolling"
				b.status = status
				b.wx, b.wy = -b.vy / R, b.vx / R
			else
				b.ax, b.ay = -slideDecel * ux / u, -slideDecel * uy / u
				b.awx, b.awy = -slideSpinAccel * uy / u, slideSpinAccel * ux / u
			end
		end
		if status == "Rolling" then
			local v = sqrt(b.vx * b.vx + b.vy * b.vy)
			if v <= rollDecel * h then
				b.vx, b.vy, b.wx, b.wy = 0, 0, 0, 0
				b.status = if abs(b.wz) > SPIN_EPSILON then "Spinning" else "Stationary"
				b.dirty = true
			else
				b.ax, b.ay = -rollDecel * b.vx / v, -rollDecel * b.vy / v
			end
		end
		b.sx, b.sy = b.vx + 0.5 * b.ax * h, b.vy + 0.5 * b.ay * h
	end

	local function advance(b: Ball, tau: number)
		local status: Status = b.status
		if isMoving(status) then
			b.x += b.sx * tau
			b.y += b.sy * tau
			b.travel += sqrt(b.sx * b.sx + b.sy * b.sy) * tau
			b.vx += b.ax * tau
			b.vy += b.ay * tau
			if status == "Sliding" then
				b.wx += b.awx * tau
				b.wy += b.awy * tau
			elseif status == "Rolling" then
				b.wx, b.wy = -b.vy / R, b.vx / R
			else
				b.z += b.vz * tau - 0.5 * g * tau * tau
				b.vz -= g * tau
			end
		end
		if status ~= "Airborne" and b.wz ~= 0 then
			local decay = spinDecel * tau
			if abs(b.wz) <= decay then
				b.wz = 0
			else
				b.wz -= if b.wz > 0 then decay else -decay
			end
		end
	end

	local function rotate(b: Ball, h: number)
		local wx, wy, wz = b.wx, b.wy, b.wz
		local w = sqrt(wx * wx + wy * wy + wz * wz)
		if w < 1e-9 then
			return
		end
		local half = 0.5 * w * h
		local s = math.sin(half) / w
		local dx, dy, dz, dw = wx * s, wy * s, wz * s, math.cos(half)
		local qx, qy, qz, qw = b.qx, b.qy, b.qz, b.qw
		local nw = dw * qw - dx * qx - dy * qy - dz * qz
		local nx = dw * qx + dx * qw + dy * qz - dz * qy
		local ny = dw * qy + dy * qw + dz * qx - dx * qz
		local nz = dw * qz + dz * qw + dx * qy - dy * qx
		local n = 1 / sqrt(nw * nw + nx * nx + ny * ny + nz * nz)
		b.qx, b.qy, b.qz, b.qw = nx * n, ny * n, nz * n, nw * n
	end

	local function setSliding(b: Ball)
		if b.status ~= "Airborne" then
			b.status = "Sliding"
		end
	end

	-- Reflects the ball off a cushion surface with inward normal (nx, ny).
	local function bounce(b: Ball, nx: number, ny: number)
		local vn = b.vx * nx + b.vy * ny
		if vn >= 0 then
			return
		end
		b.vx -= (1 + cushionE) * vn * nx
		b.vy -= (1 + cushionE) * vn * ny
		-- Friction at the contact point (tangent t = z x n) trades tangential speed for side spin.
		local tx, ty = -ny, nx
		local slip = b.vx * tx + b.vy * ty - R * b.wz
		local limit = P.CushionFriction * (1 + cushionE) * -vn
		local dvt = math.clamp(-slip / 3.5, -limit, limit)
		b.vx += dvt * tx
		b.vy += dvt * ty
		b.wz -= 2.5 * dvt / R
	end

	-- Removes any approach along the contact normal left over from step-constant acceleration.
	local function separate(b: Ball, nx: number, ny: number)
		local sn = b.sx * nx + b.sy * ny
		if sn < 0 then
			b.sx -= sn * nx
			b.sy -= sn * ny
		end
	end

	local function contactSpeed(b: Ball, nx: number, ny: number): number
		return -(b.vx * nx + b.vy * ny)
	end

	local function landOutside(b: Ball)
		if abs(b.x) <= hl and abs(b.y) <= hw then
			return
		end
		for _, pocket in pockets do
			local dx, dy = b.x - pocket.x, b.y - pocket.y
			if dx * dx + dy * dy <= pocket.radius * pocket.radius then
				return -- the pocket check catches it in the next search
			end
		end
		b.status = "OffTable"
		b.dirty = true
		emit(EventKind.OffTable, b.id, 0, 0, t)
	end

	local function recordFrame(at: number)
		local data = {}
		for _, b in balls do
			if b.dirty or isMoving(b.status) then
				b.dirty = false
				local n = #data
				data[n + 1] = b.id
				data[n + 2] = b.x
				data[n + 3] = b.y
				data[n + 4] = b.z
				data[n + 5] = b.qx
				data[n + 6] = b.qy
				data[n + 7] = b.qz
				data[n + 8] = b.qw
			end
		end
		table.insert(frames, { t = at, data = data })
	end

	local step = 0
	local function anyMoving(): boolean
		for _, b in balls do
			if isMoving(b.status) then
				return true
			end
		end
		return false
	end

	-- One fixed step of 1/SimHz with exact contact handling inside it.
	local function stepOnce()
		for _, b in balls do
			prepare(b, dt)
		end

		local elapsed = 0
		local eventsThisStep = 0
		while true do
			local remain = dt - elapsed
			local bestT = remain
			local hit = HIT_NONE
			local hitA: Ball = balls[1] -- placeholders, set together with `hit`
			local hitB: Ball = balls[1]
			local hitSegment = segments[1]
			local hitPocket = pockets[1]
			local hitEndX, hitEndY, hitEndPocket = 0, 0, 0

			if eventsThisStep < P.MaxEventsPerStep then
				for i = 1, ballCount do
					local bi = balls[i]
					local statusI: Status = bi.status
					if not isMoving(statusI) then
						continue
					end
					local airborne = statusI == "Airborne"
					local x, y, sx, sy = bi.x, bi.y, bi.sx, bi.sy

					if airborne then
						local disc = bi.vz * bi.vz + 2 * g * (bi.z - R)
						local tau = (bi.vz + sqrt(math.max(disc, 0))) / g
						if tau < bestT then
							bestT, hit, hitA = math.max(tau, 0), HIT_LAND, bi
						end
					else
						local diameter = 2 * R
						for j = 1, ballCount do
							if j == i then
								continue
							end
							local bj = balls[j]
							local statusJ: Status = bj.status
							local movingJ = isMoving(statusJ)
							if (movingJ and j < i) or not isOnTable(statusJ) or statusJ == "Airborne" then
								continue
							end
							local dpx, dpy = bj.x - x, bj.y - y
							local dvx = (if movingJ then bj.sx else 0) - sx
							local dvy = (if movingJ then bj.sy else 0) - sy
							local reach = diameter + (abs(dvx) + abs(dvy)) * bestT
							if abs(dpx) > reach or abs(dpy) > reach then
								continue
							end
							local half = dpx * dvx + dpy * dvy
							if half >= 0 then
								continue -- not approaching
							end
							local c = dpx * dpx + dpy * dpy - diameter * diameter
							local tau
							if c <= 0 then
								tau = 0
							else
								local a = dvx * dvx + dvy * dvy
								local disc = half * half - a * c
								if disc < 0 then
									continue
								end
								tau = (-half - sqrt(disc)) / a
							end
							if tau < bestT then
								bestT, hit, hitA, hitB = tau, HIT_BALL, bi, bj
							end
						end
					end

					local ex, ey = x + sx * remain, y + sy * remain
					if abs(x) <= safeX and abs(y) <= safeY and abs(ex) <= safeX and abs(ey) <= safeY then
						continue
					end

					if not airborne or bi.z - R <= P.RailHeight then
						for _, seg in segments do
							local nx, ny = seg.nx, seg.ny
							local sn = sx * nx + sy * ny
							if sn < 0 then
								local d0 = (x - seg.ax) * nx + (y - seg.ay) * ny
								if d0 >= R - PENETRATION_TOLERANCE then
									local tau = math.max((d0 - R) / -sn, 0)
									if tau < bestT then
										local u = (x + sx * tau - seg.ax) * seg.dx + (y + sy * tau - seg.ay) * seg.dy
										if u >= 0 and u <= seg.len then
											bestT, hit, hitA, hitSegment = tau, HIT_SEGMENT, bi, seg
										end
									end
								end
							end
							-- Knuckles: the segment endpoints act as round posts.
							for endpoint = 1, 2 do
								local px = if endpoint == 1 then seg.ax else seg.bx
								local py = if endpoint == 1 then seg.ay else seg.by
								local dpx, dpy = x - px, y - py
								local half = dpx * sx + dpy * sy
								if half >= 0 then
									continue
								end
								local c = dpx * dpx + dpy * dpy - R * R
								local tau
								if c <= 0 then
									tau = 0
								else
									local a = sx * sx + sy * sy
									local disc = half * half - a * c
									if disc < 0 then
										continue
									end
									tau = (-half - sqrt(disc)) / a
								end
								if tau < bestT then
									bestT, hit, hitA = tau, HIT_ENDPOINT, bi
									hitEndX, hitEndY = px, py
									hitEndPocket = if endpoint == 1 then seg.pocketA else seg.pocketB
								end
							end
						end
					end

					if not airborne then
						for _, pocket in pockets do
							local dpx, dpy = x - pocket.x, y - pocket.y
							local c = dpx * dpx + dpy * dpy - pocket.radius * pocket.radius
							local tau
							if c <= 0 then
								tau = 0
							else
								local half = dpx * sx + dpy * sy
								if half >= 0 then
									continue
								end
								local a = sx * sx + sy * sy
								local disc = half * half - a * c
								if disc < 0 then
									continue
								end
								tau = (-half - sqrt(disc)) / a
							end
							if tau < bestT then
								bestT, hit, hitA, hitPocket = tau, HIT_POCKET, bi, pocket
							end
						end
					end
				end
			end

			for _, b in balls do
				advance(b, bestT)
			end
			elapsed += bestT
			local at = t + elapsed
			if hit == HIT_NONE then
				break
			end
			eventsThisStep += 1
			local rest = dt - elapsed

			if hit == HIT_BALL then
				local a, b = hitA, hitB
				local nx, ny = b.x - a.x, b.y - a.y
				local d = sqrt(nx * nx + ny * ny)
				nx, ny = nx / d, ny / d
				local vn = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
				if vn > 0 then
					local k = 0.5 * (1 + ballE) * vn
					a.vx -= k * nx
					a.vy -= k * ny
					b.vx += k * nx
					b.vy += k * ny
				end
				emit(EventKind.BallBall, a.id, b.id, math.max(vn, 0), at)
				cueTouched = cueTouched or a.id == 0 or b.id == 0
				setSliding(a)
				setSliding(b)
				prepare(a, rest)
				prepare(b, rest)
				local closing = (a.sx - b.sx) * nx + (a.sy - b.sy) * ny
				if closing > 0 then
					local h = 0.5 * closing
					a.sx -= h * nx
					a.sy -= h * ny
					b.sx += h * nx
					b.sy += h * ny
				end
			elseif hit == HIT_SEGMENT or hit == HIT_ENDPOINT then
				local b = hitA
				local nx, ny, pocketId
				if hit == HIT_SEGMENT then
					nx, ny, pocketId = hitSegment.nx, hitSegment.ny, hitSegment.pocketId
				else
					nx, ny = b.x - hitEndX, b.y - hitEndY
					local d = sqrt(nx * nx + ny * ny)
					nx, ny, pocketId = nx / d, ny / d, hitEndPocket
				end
				local speed = contactSpeed(b, nx, ny)
				cueTouched = cueTouched or b.id == 0
				bounce(b, nx, ny)
				if pocketId == 0 then
					emit(EventKind.BallCushion, b.id, hitSegment.cushionId, speed, at)
				else
					emit(EventKind.BallJaw, b.id, pocketId, speed, at)
					if speed < P.RattleSpeed then
						emit(EventKind.Rattle, b.id, pocketId, speed, at)
					end
				end
				setSliding(b)
				prepare(b, rest)
				separate(b, nx, ny)
			elseif hit == HIT_POCKET then
				local b = hitA
				emit(EventKind.Pocketed, b.id, hitPocket.id, sqrt(b.vx * b.vx + b.vy * b.vy), at)
				b.status = "Pocketed"
				b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0
				b.sx, b.sy = 0, 0
				b.dirty = true
			elseif hit == HIT_LAND then
				local b = hitA
				local impact = -b.vz
				b.z = R
				emit(EventKind.Landed, b.id, 0, impact, at)
				if b.id == 0 then
					table.insert(cueJumps, { x0 = takeoffX, y0 = takeoffY, x1 = b.x, y1 = b.y })
					takeoffX, takeoffY = b.x, b.y
				end
				local up = P.LandRestitution * impact
				if up < P.MinBounceSpeed then
					b.vz = 0
					b.status = "Sliding"
					prepare(b, rest)
					landOutside(b)
				else
					b.vz = up
				end
			end
		end

		t += dt
		if cue and not cueTouched and isOnTable(cue.status) then
			cueCurve = math.max(cueCurve, abs((cue.x - aimX) * aimDY - (cue.y - aimY) * aimDX))
		end
		step += 1

		for _, b in balls do
			if isOnTable(b.status) then
				rotate(b, dt)
				if b.status == "Spinning" and b.wz == 0 then
					b.status = "Stationary"
					b.dirty = true
				end
				-- Safety net: anything that escaped the rails is off the table.
				if abs(b.x) > hl + 4 * R or abs(b.y) > hw + 4 * R then
					b.status = "OffTable"
					b.dirty = true
					emit(EventKind.OffTable, b.id, 0, 0, t)
				end
			end
		end
	end

	-- Residual spin in place changes nothing visible: settle it.
	local function settle()
		for _, b in balls do
			if isOnTable(b.status) and b.status ~= "Stationary" then
				b.status = "Stationary"
				b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0
				b.z = R
				b.dirty = true
			end
		end
	end

	local function hasDirty(): boolean
		for _, b in balls do
			if b.dirty then
				return true
			end
		end
		return false
	end

	local function result(): SimResult
		local finalState: { BallState } = {}
		for _, b in balls do
			table.insert(finalState, {
				id = b.id,
				x = b.x,
				y = b.y,
				status = b.status,
				qx = b.qx,
				qy = b.qy,
				qz = b.qz,
				qw = b.qw,
			})
		end

		local travel: { [number]: number } = {}
		for _, b in balls do
			travel[b.id] = b.travel
		end

		return {
			finalState = finalState,
			events = events,
			frames = frames,
			recordHz = P.RecordHz,
			duration = t,
			travel = travel,
			cueCurve = cueCurve,
			cueJumps = cueJumps,
		}
	end

	local function ball(id: number): Ball?
		for _, b in balls do
			if b.id == id then
				return b
			end
		end
		return nil
	end

	return {
		balls = balls,
		events = events,
		frames = frames,
		strike = strike,
		stepOnce = stepOnce,
		anyMoving = anyMoving,
		settle = settle,
		hasDirty = hasDirty,
		recordFrame = recordFrame,
		result = result,
		ball = ball,
		time = function(): number
			return t
		end,
		steps = function(): number
			return step
		end,
	}
end

function PoolPhysics.simulateShot(state: TableState, shot: ShotParams, opts: SimOptions?): SimResult
	local options: SimOptions = opts or {}
	local P = options.params or Physics
	local record = options.record ~= false
	local maxTime = options.maxSeconds or P.MaxShotSeconds
	local stepsPerFrame = P.SimHz // P.RecordHz
	assert(stepsPerFrame * P.RecordHz == P.SimHz, "RecordHz must divide SimHz")

	local world = makeWorld(state, P)
	local cue = world.ball(0)
	assert(cue and cue.status == "Stationary", "cue ball must be on the table")
	world.strike(cue, shot)
	if record then
		world.recordFrame(0)
	end
	while world.time() < maxTime and world.anyMoving() do
		world.stepOnce()
		local step = world.steps()
		if record and step % stepsPerFrame == 0 then
			world.recordFrame(step // stepsPerFrame / P.RecordHz)
		end
	end
	world.settle()
	if record and world.hasDirty() then
		world.recordFrame(#world.frames / P.RecordHz)
	end
	return world.result()
end

-- A live table for continuous play (speed pool). Balls are struck at any time; advance() runs
-- fixed physics steps for the elapsed time. Positions use the same model as simulateShot.
export type WorldBall = {
	id: number,
	x: number,
	y: number,
	z: number,
	status: Status,
	moving: boolean,
	qx: number,
	qy: number,
	qz: number,
	qw: number,
}

export type World = {
	strike: (id: number, shot: ShotParams) -> boolean, -- false unless the ball rests on the table
	advance: (seconds: number) -> (),
	drainEvents: () -> { Event },
	place: (id: number, x: number, y: number) -> (), -- put a ball back on the table at rest
	balls: () -> { WorldBall },
	time: () -> number,
}

function PoolPhysics.newWorld(state: TableState, params: Params?): World
	local P = params or Physics
	local world = makeWorld(state, P)
	local stepSeconds = 1 / P.SimHz
	local accumulator = 0
	local drained = 0

	local function balls(): { WorldBall }
		local list = {}
		for _, b in world.balls do
			table.insert(list, {
				id = b.id,
				x = b.x,
				y = b.y,
				z = b.z,
				status = b.status,
				moving = isMoving(b.status),
				qx = b.qx,
				qy = b.qy,
				qz = b.qz,
				qw = b.qw,
			})
		end
		return list
	end

	return {
		strike = function(id: number, shot: ShotParams): boolean
			local b = world.ball(id)
			if not b or b.status ~= "Stationary" and b.status ~= "Spinning" then
				return false
			end
			world.strike(b, shot)
			return true
		end,
		advance = function(seconds: number)
			accumulator = math.min(accumulator + seconds, 0.25) -- never spiral after a hitch
			while accumulator >= stepSeconds do
				accumulator -= stepSeconds
				world.stepOnce()
			end
		end,
		drainEvents = function(): { Event }
			local fresh = {}
			for i = drained + 1, #world.events do
				table.insert(fresh, world.events[i])
			end
			drained = #world.events
			return fresh
		end,
		place = function(id: number, x: number, y: number)
			local b = world.ball(id)
			if b then
				b.x, b.y, b.z = x, y, state.geometry.ballRadius
				b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0
				b.status = "Stationary"
			end
		end,
		balls = balls,
		time = world.time,
	}
end

return PoolPhysics
