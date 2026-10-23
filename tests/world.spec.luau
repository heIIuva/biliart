--!strict
-- Continuous physics world (speed pool) against the one-shot simulation.
local PoolPhysics = require("../src/shared/Pool/PoolPhysics")
local Rack = require("../src/shared/Pool/Rack")
local TableGeometry = require("../src/shared/Pool/TableGeometry")

local Kind = PoolPhysics.EventKind
local geo = TableGeometry.get("Standard")
local SHOT = { angle = 0, power = 1, spinX = 0, spinY = 0, elevation = 0 }

local function settled(world: PoolPhysics.World): boolean
	for _, b in world.balls() do
		if b.moving then
			return false
		end
	end
	return true
end

return {
	["world: a strike plays out exactly like simulateShot"] = function()
		local balls = Rack.eightBall(geo, 4)
		local sim = PoolPhysics.simulateShot({ geometry = geo, balls = balls }, SHOT, { record = false })
		local world = PoolPhysics.newWorld({ geometry = geo, balls = balls })
		assert(world.strike(0, SHOT), "strike accepted")
		local guard = 0
		repeat
			world.advance(1 / 60)
			guard += 1
		until settled(world) or guard > 60 * 20
		local byId = {}
		for _, b in world.balls() do
			byId[b.id] = b
		end
		for _, b in sim.finalState do
			local w = byId[b.id]
			assert(w.status == b.status or (b.status == "Stationary" and w.status == "Spinning"), `ball {b.id} status`)
			if b.status == "Stationary" then
				assert(math.abs(w.x - b.x) < 1e-9 and math.abs(w.y - b.y) < 1e-9, `ball {b.id} position differs`)
			end
		end
	end,

	["world: two cue balls struck at different times, no NaN, deterministic"] = function()
		local function run(): { PoolPhysics.WorldBall }
			local balls = Rack.eightBall(geo, 9)
			table.insert(balls, { id = 16, x = geo.footSpotX + 0.4, y = 0.3, status = "Stationary" })
			local world = PoolPhysics.newWorld({ geometry = geo, balls = balls })
			assert(world.strike(0, SHOT), "first cue")
			world.advance(0.2)
			assert(
				world.strike(16, { angle = math.pi, power = 0.6, spinX = 0, spinY = 0, elevation = 0 }),
				"second cue"
			)
			for _ = 1, 600 do
				world.advance(1 / 60)
			end
			return world.balls()
		end
		local a, b = run(), run()
		for i, ball in a do
			assert(ball.x == ball.x and ball.y == ball.y, "no NaN")
			assert(ball.x == b[i].x and ball.y == b[i].y, "deterministic")
		end
	end,

	["world: a moving ball can't be struck, events drain once, placed balls rest"] = function()
		local world = PoolPhysics.newWorld({ geometry = geo, balls = Rack.eightBall(geo, 2) })
		assert(world.strike(0, SHOT), "first strike")
		world.advance(0.05)
		assert(not world.strike(0, SHOT), "the cue ball is still moving")
		local first = world.drainEvents()
		assert(#first > 0 and first[1].kind == Kind.CueStrike, "strike event first")
		assert(#world.drainEvents() == 0, "nothing new without stepping")
		world.place(0, geo.headSpotX, 0)
		for _, b in world.balls() do
			if b.id == 0 then
				assert(b.status == "Stationary" and b.x == geo.headSpotX, "placed at rest")
			end
		end
	end,
}
