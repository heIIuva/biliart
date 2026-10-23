--!strict
-- The aim guide must agree with what the simulation actually does on a plain (no spin) shot.
local AimPredictor = require("../src/shared/Pool/AimPredictor")
local Physics = require("../src/shared/Config/Physics")
local PoolPhysics = require("../src/shared/Pool/PoolPhysics")
local TableGeometry = require("../src/shared/Pool/TableGeometry")

local Kind = PoolPhysics.EventKind
local STRIDE = PoolPhysics.FRAME_STRIDE
local geo = TableGeometry.get("Standard")
local R = geo.ballRadius

local function lcg(seed: number): () -> number
	local state = seed
	return function()
		state = state * 48271 % 2147483647
		return state / 2147483647
	end
end

local function randomScene(random: () -> number): { PoolPhysics.BallState }
	local balls: { PoolPhysics.BallState } = {}
	local count = 2 + math.floor(random() * 5)
	while #balls < count do
		local x = (random() * 2 - 1) * (geo.halfLength - 3 * R)
		local y = (random() * 2 - 1) * (geo.halfWidth - 3 * R)
		local free = true
		for _, b in balls do
			free = free and (b.x - x) ^ 2 + (b.y - y) ^ 2 > (2.2 * R) ^ 2
		end
		if free then
			table.insert(balls, { id = #balls, x = x, y = y, status = "Stationary" })
		end
	end
	return balls
end

-- First thing the cue ball touches in the simulation.
local function firstCueContact(result: PoolPhysics.SimResult): PoolPhysics.Event
	for _, e in result.events do
		local cueEvent = e.a == 0 or (e.kind == Kind.BallBall and e.b == 0)
		local contact = e.kind == Kind.BallBall
			or e.kind == Kind.BallCushion
			or e.kind == Kind.BallJaw
			or e.kind == Kind.Pocketed
		if cueEvent and contact then
			return e
		end
	end
	error("cue ball touched nothing")
end

local function positionAfter(result: PoolPhysics.SimResult, id: number, t: number): (number, number)
	for _, frame in result.frames do
		if frame.t > t then
			local data = frame.data
			for i = 1, #data, STRIDE do
				if data[i] == id then
					return data[i + 1], data[i + 2]
				end
			end
		end
	end
	error(`ball {id} not recorded after {t}`)
end

return {
	["aim guide matches the first contact of the simulation"] = function()
		local random = lcg(2024)
		local counts = { Ball = 0, Cushion = 0, Pocket = 0 }
		for scene = 1, 300 do
			local balls = randomScene(random)
			local angle = random() * 2 * math.pi
			local aim = AimPredictor.predict(geo, balls, angle)
			local result = PoolPhysics.simulateShot(
				{ geometry = geo, balls = balls },
				{ angle = angle, power = 2 / Physics.MaxCueSpeed, spinX = 0, spinY = 0, elevation = 0 }
			)
			local first = firstCueContact(result)
			local label = `scene {scene}: predicted {aim.kind}, got event {first.kind}`
			counts[aim.kind] += 1

			if aim.kind == "Ball" then
				assert(first.kind == Kind.BallBall and first.b == aim.targetId, label)
				local x0, y0 = positionAfter(result, first.b, first.t)
				local x1, y1 = positionAfter(result, first.b, first.t + 2 / 60)
				local moved = math.atan2(y1 - y0, x1 - x0)
				local predicted = math.atan2(aim.targetDirY, aim.targetDirX)
				local diff = math.abs((moved - predicted + math.pi) % (2 * math.pi) - math.pi)
				assert(math.deg(diff) < 1, `{label}: object ball direction off by {math.deg(diff)}°`)
			elseif aim.kind == "Cushion" then
				assert(first.kind == Kind.BallCushion or first.kind == Kind.BallJaw, label)
			elseif aim.kind == "Pocket" then
				assert(first.kind == Kind.Pocketed, label)
			else
				error(label)
			end
		end
		assert(counts.Ball > 20 and counts.Cushion > 20, `too few cases: {counts.Ball} ball, {counts.Cushion} cushion`)
	end,
}
