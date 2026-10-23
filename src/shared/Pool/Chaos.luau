--!strict
-- Chaos mode effects as pure functions (tested in Lune). Randomness comes from the caller.

local Chaos = require("../Config/Chaos")
local Physics = require("../Config/Physics")
local PoolPhysics = require("./PoolPhysics")
local PoolRules = require("./PoolRules")
local TableGeometry = require("./TableGeometry")

local ChaosEffects = {}

-- Weighted pick of a bonus.
function ChaosEffects.pickBonus(random: () -> number): Chaos.Bonus
	local total = 0
	for _, bonus in Chaos.Bonuses do
		total += bonus.weight
	end
	local roll = random() * total
	for _, bonus in Chaos.Bonuses do
		roll -= bonus.weight
		if roll <= 0 then
			return bonus
		end
	end
	return Chaos.Bonuses[#Chaos.Bonuses]
end

function ChaosEffects.pickGolden(balls: { PoolPhysics.BallState }, count: number, random: () -> number): { number }
	local pool = {}
	for _, b in balls do
		if b.id ~= 0 and b.id ~= 8 and b.status == "Stationary" then
			table.insert(pool, b.id)
		end
	end
	local chosen = {}
	for _ = 1, math.min(count, #pool) do
		local index = math.floor(random() * #pool) + 1
		table.insert(chosen, table.remove(pool, index) :: number)
	end
	return chosen
end

-- Earthquake: nudge every resting ball a little, never into another ball or out of the field.
function ChaosEffects.earthquake(
	geometry: TableGeometry.Geometry,
	balls: { PoolPhysics.BallState },
	random: () -> number
): { PoolPhysics.BallState }
	local out = table.clone(balls)
	local R = geometry.ballRadius
	for i, b in out do
		if b.status == "Stationary" then
			for _ = 1, 6 do
				local angle = random() * 2 * math.pi
				local distance = random() * Chaos.EarthquakeShift
				local x, y = b.x + math.cos(angle) * distance, b.y + math.sin(angle) * distance
				local ok = math.abs(x) <= geometry.halfLength - R and math.abs(y) <= geometry.halfWidth - R
				for j, other in out do
					if
						ok
						and j ~= i
						and other.status == "Stationary"
						and (other.x - x) ^ 2 + (other.y - y) ^ 2 < (2 * R) ^ 2
					then
						ok = false
					end
				end
				if ok then
					out[i] = { id = b.id, x = x, y = y, status = b.status, qx = b.qx, qy = b.qy, qz = b.qz, qw = b.qw }
					break
				end
			end
		end
	end
	return out
end

-- Physics overrides for one shot.
function ChaosEffects.params(moonJump: boolean, superShot: boolean): PoolPhysics.Params
	local params = table.clone(Physics)
	if moonJump then
		params.JumpRestitution = Chaos.MoonJumpRestitution
	end
	if superShot then
		params.MaxCueSpeed = Physics.MaxCueSpeed * Chaos.SuperShotSpeed
	end
	return params
end

-- Glitch: one of the shooter's balls still on the table "phases" into a pocket at the end of the
-- shot. Edits the result in place (final state + a Pocketed event); returns the ball id or nil.
function ChaosEffects.glitch(sim: PoolPhysics.SimResult, group: PoolRules.Group?, random: () -> number): number?
	local candidates = {}
	for _, b in sim.finalState do
		local own = if group then PoolRules.groupOf(b.id) == group else (b.id ~= 0 and b.id ~= 8)
		if b.status == "Stationary" and own then
			table.insert(candidates, b)
		end
	end
	if #candidates == 0 then
		return nil
	end
	local ball = candidates[math.floor(random() * #candidates) + 1]
	ball.status = "Pocketed"
	table.insert(sim.events, {
		t = sim.duration,
		kind = PoolPhysics.EventKind.Pocketed,
		a = ball.id,
		b = math.floor(random() * 6) + 1,
		speed = 0,
	})
	return ball.id
end

return ChaosEffects
