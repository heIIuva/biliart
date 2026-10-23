--!strict
-- Aim guide: casts the cue ball (a circle of radius R) along the aim direction and reports the
-- first thing it would touch, using the same TableGeometry as the simulation. Straight line only:
-- masse curves and jumps are not predicted. Pure Luau: no Roblox API.

local PoolPhysics = require("./PoolPhysics")
local TableGeometry = require("./TableGeometry")

export type HitKind = "Ball" | "Cushion" | "Pocket" | "None"

export type Aim = {
	kind: HitKind,
	ghostX: number, -- cue ball center at the moment of contact
	ghostY: number,
	targetId: number?, -- object ball (kind == "Ball")
	targetDirX: number, -- where the object ball goes (kind == "Ball")
	targetDirY: number,
	cueDirX: number, -- where the cue ball goes after a stun hit / rebound (zero for a full hit)
	cueDirY: number,
}

local AimPredictor = {}

-- Smallest s >= 0 where |p + d*s - c| == radius, for a unit direction d; nil if never.
local function circleHit(
	px: number,
	py: number,
	dx: number,
	dy: number,
	cx: number,
	cy: number,
	radius: number
): number?
	local ox, oy = px - cx, py - cy
	local half = ox * dx + oy * dy
	local c = ox * ox + oy * oy - radius * radius
	if c <= 0 then
		return if half < 0 then 0 else nil
	end
	if half >= 0 then
		return nil
	end
	local disc = half * half - c
	if disc < 0 then
		return nil
	end
	return -half - math.sqrt(disc)
end

-- cueId: the shooter's cue ball (speed pool gives player 2 its own); defaults to 0.
function AimPredictor.predict(
	geometry: TableGeometry.Geometry,
	balls: { PoolPhysics.BallState },
	angle: number,
	cueId: number?
): Aim
	local R = geometry.ballRadius
	local cue: PoolPhysics.BallState? = nil
	local own = cueId or 0
	for _, b in balls do
		if b.id == own then
			cue = b
		end
	end
	assert(cue, "no cue ball")
	local px, py = cue.x, cue.y
	local dx, dy = math.cos(angle), math.sin(angle)

	local best = math.huge
	local kind: HitKind = "None"
	local target: PoolPhysics.BallState? = nil
	local normalX, normalY = 0, 0

	for _, b in balls do
		if b.id ~= own and b.status == "Stationary" then
			local s = circleHit(px, py, dx, dy, b.x, b.y, 2 * R)
			if s and s < best then
				best, kind, target = s, "Ball", b
			end
		end
	end

	for _, seg in geometry.segments do
		local sn = dx * seg.nx + dy * seg.ny
		if sn < 0 then
			local d0 = (px - seg.ax) * seg.nx + (py - seg.ay) * seg.ny
			local s = (d0 - R) / -sn
			if s >= 0 and s < best then
				local u = (px + dx * s - seg.ax) * seg.dx + (py + dy * s - seg.ay) * seg.dy
				if u >= 0 and u <= seg.len then
					best, kind, normalX, normalY = s, "Cushion", seg.nx, seg.ny
				end
			end
		end
		for endpoint = 1, 2 do
			local ex = if endpoint == 1 then seg.ax else seg.bx
			local ey = if endpoint == 1 then seg.ay else seg.by
			local s = circleHit(px, py, dx, dy, ex, ey, R)
			if s and s < best then
				local gx, gy = px + dx * s, py + dy * s
				best, kind, normalX, normalY = s, "Cushion", (gx - ex) / R, (gy - ey) / R
			end
		end
	end

	for _, pocket in geometry.pockets do
		local s = circleHit(px, py, dx, dy, pocket.x, pocket.y, pocket.radius)
		if s and s < best then
			best, kind = s, "Pocket"
		end
	end

	if kind == "None" then
		return { kind = kind, ghostX = px, ghostY = py, targetDirX = 0, targetDirY = 0, cueDirX = 0, cueDirY = 0 }
	end

	local gx, gy = px + dx * best, py + dy * best
	local aim: Aim = {
		kind = kind,
		ghostX = gx,
		ghostY = gy,
		targetDirX = 0,
		targetDirY = 0,
		cueDirX = 0,
		cueDirY = 0,
	}
	if kind == "Ball" and target then
		local nx, ny = (target.x - gx) / (2 * R), (target.y - gy) / (2 * R)
		aim.targetId = target.id
		aim.targetDirX, aim.targetDirY = nx, ny
		-- Equal masses, no spin: the cue ball leaves along the tangent line.
		local along = dx * nx + dy * ny
		local tx, ty = dx - along * nx, dy - along * ny
		local length = math.sqrt(tx * tx + ty * ty)
		if length > 1e-6 then
			aim.cueDirX, aim.cueDirY = tx / length, ty / length
		end
	elseif kind == "Cushion" then
		local along = dx * normalX + dy * normalY
		aim.cueDirX, aim.cueDirY = dx - 2 * along * normalX, dy - 2 * along * normalY
	end
	return aim
end

return AimPredictor
