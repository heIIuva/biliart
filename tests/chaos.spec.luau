--!strict
-- Chaos mode effects and the trick of the week.
local Chaos = require("../src/shared/Config/Chaos")
local ChaosEffects = require("../src/shared/Pool/Chaos")
local Physics = require("../src/shared/Config/Physics")
local PoolPhysics = require("../src/shared/Pool/PoolPhysics")
local Rack = require("../src/shared/Pool/Rack")
local ShotClassifier = require("../src/shared/Pool/ShotClassifier")
local TableGeometry = require("../src/shared/Pool/TableGeometry")
local TrickConfig = require("../src/shared/Config/Tricks")
local Tricks = require("../src/shared/Pool/Tricks")

local geo = TableGeometry.get("Standard")

local function lcg(seed: number): () -> number
	local state = seed
	return function()
		state = state * 48271 % 2147483647
		return state / 2147483647
	end
end

return {
	["chaos: bonuses follow the weights roughly, golden balls are unique object balls"] = function()
		local random = lcg(7)
		local counts: { [string]: number } = {}
		for _ = 1, 2000 do
			local bonus = ChaosEffects.pickBonus(random)
			counts[bonus.id] = (counts[bonus.id] or 0) + 1
		end
		for _, bonus in Chaos.Bonuses do
			assert((counts[bonus.id] or 0) > 200, `{bonus.id} almost never picked`)
		end
		local golden = ChaosEffects.pickGolden(Rack.eightBall(geo, 1), 2, random)
		assert(#golden == 2 and golden[1] ~= golden[2], "two different balls")
		for _, id in golden do
			assert(id ~= 0 and id ~= 8, "never the cue ball or the 8")
		end
	end,

	["chaos: earthquake moves balls a little and never overlaps or leaves the field"] = function()
		local random = lcg(11)
		local before = Rack.eightBall(geo, 2)
		local after = ChaosEffects.earthquake(geo, before, random)
		local moved = 0
		for i, b in after do
			local d = math.sqrt((b.x - before[i].x) ^ 2 + (b.y - before[i].y) ^ 2)
			assert(d <= Chaos.EarthquakeShift + 1e-9, "small shift")
			moved += if d > 0 then 1 else 0
			assert(math.abs(b.x) <= geo.halfLength - geo.ballRadius, "inside")
			for j, other in after do
				if j ~= i then
					assert((other.x - b.x) ^ 2 + (other.y - b.y) ^ 2 >= (2 * geo.ballRadius) ^ 2 - 1e-12, "no overlap")
				end
			end
		end
		assert(moved > 0, "something moved")
	end,

	["chaos: moon jump and super shot change only their parameters"] = function()
		local params = ChaosEffects.params(true, true)
		assert(params.JumpRestitution == Chaos.MoonJumpRestitution, "moon jump")
		assert(params.MaxCueSpeed == Physics.MaxCueSpeed * Chaos.SuperShotSpeed, "super shot")
		assert(Physics.JumpRestitution ~= Chaos.MoonJumpRestitution, "the base config is untouched")
	end,

	["glitch: an own ball phases into a pocket and earns QUANTUM"] = function()
		local sim = PoolPhysics.simulateShot(
			{ geometry = geo, balls = Rack.eightBall(geo, 3) },
			{ angle = 0, power = 0.2, spinX = 0, spinY = 0, elevation = 0 },
			{ record = false }
		)
		local id = ChaosEffects.glitch(sim, "Solids", lcg(5))
		assert(id and id >= 1 and id <= 7, "a solid")
		local last = sim.events[#sim.events]
		assert(last.kind == PoolPhysics.EventKind.Pocketed and last.a == id, "pocketed event at the end")
		local quantum = ShotClassifier.byId("QUANTUM")
		assert(quantum and quantum.kind == "Glitch", "glitch title exists")
	end,

	["trick of the week: one per week, every trick has a working solution"] = function()
		assert(Tricks.forTime(0) ~= nil, "a trick for any time")
		assert(Tricks.forTime(0).id ~= Tricks.forTime(7 * 86400).id or #TrickConfig.List == 1, "rotates weekly")
		for _, trick in TrickConfig.List do
			local solution = trick.solution
			assert(solution, `{trick.id}: no solution`)
			assert(Tricks.solved(trick, Tricks.play(trick, solution)), `{trick.id}: stored solution fails`)
			local miss = Tricks.play(
				trick,
				{ angle = solution.angle + math.pi, power = 0.3, spinX = 0, spinY = 0, elevation = 0 }
			)
			assert(not Tricks.solved(trick, miss), `{trick.id}: shooting backwards should not solve it`)
		end
	end,
}
