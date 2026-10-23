--!strict
local Physics = require("../src/shared/Config/Physics")
local PoolPhysics = require("../src/shared/Pool/PoolPhysics")
local Rack = require("../src/shared/Pool/Rack")
local TableGeometry = require("../src/shared/Pool/TableGeometry")

local Kind = PoolPhysics.EventKind
local STRIDE = PoolPhysics.FRAME_STRIDE
local geo = TableGeometry.get("Standard")
local R = geo.ballRadius
local HL, HW = geo.halfLength, geo.halfWidth

type Placement = { id: number, x: number, y: number }

-- Coarse stepping: at 30 Hz a max-speed ball moves 32 cm per step (more than 5 diameters),
-- so only exact time-of-impact detection can keep it from passing through.
local coarse = table.clone(Physics)
coarse.SimHz = 30
coarse.RecordHz = 30

local function simulate(
	placements: { Placement },
	shot: { [string]: number },
	params: PoolPhysics.Params?
): PoolPhysics.SimResult
	local balls: { PoolPhysics.BallState } = {}
	for _, p in placements do
		table.insert(balls, { id = p.id, x = p.x, y = p.y, status = "Stationary" })
	end
	return PoolPhysics.simulateShot({ geometry = geo, balls = balls }, {
		angle = shot.angle or 0,
		power = shot.power or 0.3,
		spinX = shot.spinX or 0,
		spinY = shot.spinY or 0,
		elevation = shot.elevation or 0,
	}, { params = params })
end

local function powerFor(speed: number): number
	return speed / Physics.MaxCueSpeed
end

local function final(result: PoolPhysics.SimResult, id: number): PoolPhysics.BallState
	for _, b in result.finalState do
		if b.id == id then
			return b
		end
	end
	error(`ball {id} missing`)
end

-- Last recorded position of a ball at or before time t: x, y, z.
local function positionAt(result: PoolPhysics.SimResult, id: number, t: number): (number, number, number)
	local x, y, z = math.huge, math.huge, math.huge
	for _, frame in result.frames do
		if frame.t > t + 1e-9 then
			break
		end
		local data = frame.data
		for i = 1, #data, STRIDE do
			if data[i] == id then
				x, y, z = data[i + 1], data[i + 2], data[i + 3]
			end
		end
	end
	assert(x ~= math.huge, `ball {id} never recorded before t={t}`)
	return x, y, z
end

local function eventsOf(result: PoolPhysics.SimResult, kind: number): { PoolPhysics.Event }
	local found = {}
	for _, e in result.events do
		if e.kind == kind then
			table.insert(found, e)
		end
	end
	return found
end

local function firstEvent(result: PoolPhysics.SimResult, kind: number, a: number?, b: number?): PoolPhysics.Event
	for _, e in result.events do
		if e.kind == kind and (a == nil or e.a == a) and (b == nil or e.b == b) then
			return e
		end
	end
	error(`no event kind={kind} a={a} b={b}`)
end

local function hasEvent(result: PoolPhysics.SimResult, kind: number, a: number?): boolean
	for _, e in result.events do
		if e.kind == kind and (a == nil or e.a == a) then
			return true
		end
	end
	return false
end

local function breakShot(seed: number): PoolPhysics.SimResult
	return PoolPhysics.simulateShot(
		{ geometry = geo, balls = Rack.eightBall(geo, seed) },
		{ angle = 0, power = 1, spinX = 0, spinY = 0, elevation = 0 }
	)
end

-- Cue ball (0) at (0, -0.07) shooting +Y into ball 1 at the origin; ball 1 heads for side pocket 5.
local function headOn(spinY: number): (PoolPhysics.SimResult, number)
	local result = simulate({ { id = 0, x = 0, y = -0.07 }, { id = 1, x = 0, y = 0 } }, {
		angle = math.pi / 2,
		power = powerFor(3),
		spinY = spinY,
	})
	local contact = firstEvent(result, Kind.BallBall, 0, 1)
	local _, contactY = positionAt(result, 0, contact.t)
	return result, contactY
end

return {
	["straight shot slows down monotonically and stops"] = function()
		local result = simulate({ { id = 0, x = -0.5, y = 0 } }, { power = powerFor(0.6) })
		local lastSpeed = math.huge
		local px, py = positionAt(result, 0, 0)
		for k = 2, #result.frames do
			local frame = result.frames[k]
			local x, y = positionAt(result, 0, frame.t)
			local dt = frame.t - result.frames[k - 1].t
			local speed = math.sqrt((x - px) ^ 2 + (y - py) ^ 2) / dt
			assert(speed <= lastSpeed + 1e-6, `speed grew at t={frame.t}: {lastSpeed} -> {speed}`)
			lastSpeed, px, py = speed, x, y
		end
		local cue = final(result, 0)
		assert(cue.status == "Stationary", "cue ball must stop")
		assert(cue.x > -0.5 + 0.3, `cue ball barely moved: x={cue.x}`)
		assert(math.abs(cue.y) < 1e-9, `cue ball drifted sideways: y={cue.y}`)
		assert(#eventsOf(result, Kind.BallCushion) == 0, "should stop before the rail")
	end,

	["stun: head-on hit without spin stops the cue ball"] = function()
		local result, contactY = headOn(0)
		local cue = final(result, 0)
		-- With ball restitution 0.95 the cue ball keeps 2.5% of its speed: a few cm of creep is physical.
		assert(math.abs(cue.y - contactY) < 0.05, `cue ball should stay near contact, moved {cue.y - contactY}`)
		local _, objectY = positionAt(result, 1, firstEvent(result, Kind.BallBall, 0, 1).t + 0.1)
		assert(objectY > 0.2, `object ball should run away, y={objectY}`)
	end,

	-- Reversing a 3 m/s draw shot takes ~0.55 s of sliding, so positions are checked 0.6 s after contact.
	["follow and draw: top spin goes forward, bottom spin comes back"] = function()
		local follow, followContact = headOn(Physics.MaxTipOffset)
		local followT = firstEvent(follow, Kind.BallBall, 0, 1).t
		local _, followY = positionAt(follow, 0, followT + 0.6)
		assert(followY > followContact + 0.1, `follow: cue ball should move forward, dy={followY - followContact}`)

		local draw, drawContact = headOn(-Physics.MaxTipOffset)
		local drawT = firstEvent(draw, Kind.BallBall, 0, 1).t
		local _, drawY = positionAt(draw, 0, drawT + 0.6)
		assert(drawY < drawContact - 0.1, `draw: cue ball should come back, dy={drawY - drawContact}`)
	end,

	["cushion: angle out is close to angle in without side spin"] = function()
		local result = simulate({ { id = 0, x = -0.7, y = 0.2 } }, { angle = math.pi / 4, power = powerFor(2) })
		local hit = firstEvent(result, Kind.BallCushion, 0)
		assert(hit.b == 5, `expected top-left rail, got {hit.b}`)
		-- Directions from adjacent frames right before and right after the contact: further on,
		-- the leftover roll bends the path (physically correct, but not the rebound angle).
		local frame = 1 / 60
		local x0, y0 = positionAt(result, 0, hit.t - frame)
		local x1, y1 = positionAt(result, 0, hit.t)
		local x2, y2 = positionAt(result, 0, hit.t + frame)
		local x3, y3 = positionAt(result, 0, hit.t + 2 * frame)
		-- Angles from the cushion normal (rail along X).
		local angleIn = math.deg(math.atan2(math.abs(x1 - x0), math.abs(y1 - y0)))
		local angleOut = math.deg(math.atan2(math.abs(x3 - x2), math.abs(y3 - y2)))
		assert(math.abs(angleIn - angleOut) < 6, `in {angleIn}°, out {angleOut}°`)
	end,

	["side spin bends the cushion rebound"] = function()
		local function outX(spinX: number): number
			local result = simulate({ { id = 0, x = -0.5, y = 0 } }, {
				angle = math.pi / 2,
				power = powerFor(2),
				spinX = spinX,
			})
			local hit = firstEvent(result, Kind.BallCushion, 0)
			local x = positionAt(result, 0, hit.t + 0.15)
			return x
		end
		assert(outX(0.5) > -0.5 + 0.01, "right english should rebound to the right (+X)")
		assert(outX(-0.5) < -0.5 - 0.01, "left english should rebound to the left (-X)")
	end,

	["no tunneling through balls at max speed (coarse 30 Hz steps)"] = function()
		for _, gap in { 1e-6, 0.001, 0.05, 0.2, 1.0 } do
			local result = simulate(
				{ { id = 0, x = -0.6, y = 0 }, { id = 1, x = -0.6 + 2 * R + gap, y = 0 } },
				{ power = 1 },
				coarse
			)
			local contact = firstEvent(result, Kind.BallBall, 0, 1)
			local cx = positionAt(result, 0, contact.t)
			local ox = positionAt(result, 1, contact.t + 1 / 30)
			assert(cx < ox, `cue ball passed the object ball (gap {gap})`)
		end
	end,

	["no tunneling through cushions at max speed (coarse 30 Hz steps)"] = function()
		local result = simulate({ { id = 0, x = -0.4, y = 0 } }, { angle = math.pi / 2 + 0.3, power = 1 }, coarse)
		assert(#eventsOf(result, Kind.BallCushion) > 0, "should hit cushions")
		for _, frame in result.frames do
			local data = frame.data
			for i = 1, #data, STRIDE do
				local x, y = data[i + 1], data[i + 2]
				local inField = math.abs(x) <= HL - R + 1e-6 and math.abs(y) <= HW - R + 1e-6
				assert(inField or hasEvent(result, Kind.Pocketed, 0), `escaped the field at ({x}, {y})`)
			end
		end
		local cue = final(result, 0)
		assert(cue.status ~= "OffTable", "cue ball left the table")
	end,

	["ball aimed at the corner pocket center is potted"] = function()
		local result = simulate({ { id = 0, x = HL - 0.4, y = HW - 0.4 } }, {
			angle = math.pi / 4,
			power = powerFor(1.5),
		})
		local potted = firstEvent(result, Kind.Pocketed, 0)
		assert(potted.b == 6, `expected pocket 6, got {potted.b}`)
		assert(final(result, 0).status == "Pocketed", "cue ball should be pocketed")
	end,

	["Chinese8: narrow pockets still take a ball aimed at the center"] = function()
		local chinese = TableGeometry.get("Chinese8")
		local result = PoolPhysics.simulateShot({
			geometry = chinese,
			balls = { { id = 0, x = -chinese.halfLength + 0.4, y = -chinese.halfWidth + 0.4, status = "Stationary" } },
		}, { angle = -3 * math.pi / 4, power = powerFor(1.5), spinX = 0, spinY = 0, elevation = 0 })
		assert(firstEvent(result, Kind.Pocketed, 0).b == 1, "expected pocket 1")
	end,

	["slow ball into the jaw rattles out"] = function()
		local jawX, jawY = HL - 0.12 / math.sqrt(2), HW -- long-rail jaw point of pocket 6
		local fromX, fromY = jawX + 0.05, jawY - 0.3 -- from the pocket side, so the rail line is not hit first
		local result = simulate({ { id = 0, x = fromX, y = fromY } }, {
			angle = math.atan2(jawY - fromY, jawX - fromX),
			power = powerFor(0.5),
		})
		local jaw = firstEvent(result, Kind.BallJaw, 0)
		assert(jaw.b == 6, `expected jaw of pocket 6, got {jaw.b}`)
		assert(hasEvent(result, Kind.Rattle, 0), "slow jaw hit should emit Rattle")
		assert(not hasEvent(result, Kind.Pocketed, 0), "ball should not drop")
	end,

	["break: at least 4 balls reach a cushion"] = function()
		for seed = 1, 5 do
			local result = breakShot(seed)
			local touched, count = {}, 0
			for _, e in eventsOf(result, Kind.BallCushion) do
				if e.a ~= 0 and not touched[e.a] then
					touched[e.a] = true
					count += 1
				end
			end
			assert(count >= 4, `seed {seed}: only {count} balls touched a cushion`)
		end
	end,

	["deterministic: same input, same result"] = function()
		local a, b = breakShot(7), breakShot(7)
		assert(#a.events == #b.events, "event count differs")
		for i, e in a.events do
			local f = b.events[i]
			assert(e.kind == f.kind and e.t == f.t and e.a == f.a and e.b == f.b, `event {i} differs`)
		end
		for i, s in a.finalState do
			local u = b.finalState[i]
			assert(s.id == u.id and s.x == u.x and s.y == u.y and s.status == u.status, `ball {s.id} differs`)
		end
	end,

	["jump: elevated cue makes the ball fly and land"] = function()
		local result = simulate({ { id = 0, x = -0.6, y = 0 } }, { power = 0.6, elevation = math.rad(50) })
		local up = firstEvent(result, Kind.Airborne, 0)
		local down = firstEvent(result, Kind.Landed, 0)
		assert(down.t > up.t, "should land after taking off")
		local _, _, z = positionAt(result, 0, (up.t + down.t) / 2)
		assert(z > R + 0.005, `ball should be in the air, z={z}`)
	end,

	["jump: an airborne cue ball passes over a ball"] = function()
		local result = simulate(
			{ { id = 0, x = -0.6, y = 0 }, { id = 1, x = -0.5, y = 0 } },
			{ power = 0.6, elevation = math.rad(50) }
		)
		local landed = firstEvent(result, Kind.Landed, 0)
		local x = positionAt(result, 0, landed.t)
		assert(x > -0.5, `cue ball should land beyond the object ball, x={x}`)
		local touched = false
		for _, e in eventsOf(result, Kind.BallBall) do
			touched = touched or e.t < landed.t
		end
		assert(not touched, "no contact while airborne")
	end,

	["masse: elevated cue with side spin curves the path"] = function()
		local result = simulate({ { id = 0, x = -0.6, y = 0 } }, {
			power = powerFor(1.2),
			spinX = 0.5,
			elevation = math.rad(55),
		})
		assert(not hasEvent(result, Kind.Airborne, 0), "should stay on the cloth")
		local cue = final(result, 0)
		assert(cue.y < -0.05, `right masse should curve to the right (-Y), y={cue.y}`)
	end,

	["benchmark: break under 30 ms"] = function()
		local runs = 10
		local start = os.clock()
		for seed = 1, runs do
			breakShot(seed)
		end
		local ms = (os.clock() - start) / runs * 1000
		print(string.format("  break simulation: %.2f ms avg over %d runs", ms, runs))
		assert(ms < 30, `break took {ms} ms`)
	end,
}
