--!strict
-- Trick of the week helpers (pure, tested): which trick runs this week, its layout, success check,
-- and a solution search used by tools/find_tricks.luau.

local PoolPhysics = require("./PoolPhysics")
local Progression = require("../Game/Progression")
local TableGeometry = require("./TableGeometry")
local TrickConfig = require("../Config/Tricks")

local Kind = PoolPhysics.EventKind
local geo = TableGeometry.get("Standard")

local Tricks = {}

function Tricks.forTime(time: number): TrickConfig.Trick
	local list = TrickConfig.List
	return list[Progression.weekIndex(time) % #list + 1]
end

function Tricks.layout(trick: TrickConfig.Trick): { PoolPhysics.BallState }
	local balls: { PoolPhysics.BallState } = {}
	for _, b in trick.balls do
		table.insert(balls, { id = b[1], x = b[2], y = b[3], status = "Stationary" })
	end
	return balls
end

-- Success: the target dropped and the cue ball stayed on the table.
function Tricks.solved(trick: TrickConfig.Trick, sim: PoolPhysics.SimResult): boolean
	local potted, scratched = false, false
	for _, e in sim.events do
		if e.kind == Kind.Pocketed then
			potted = potted or e.a == trick.target
			scratched = scratched or e.a == 0
		elseif e.kind == Kind.OffTable and e.a == 0 then
			scratched = true
		end
	end
	return potted and not scratched
end

function Tricks.play(trick: TrickConfig.Trick, shot: PoolPhysics.ShotParams): PoolPhysics.SimResult
	return PoolPhysics.simulateShot({ geometry = geo, balls = Tricks.layout(trick) }, shot, { record = false })
end

-- Brute-force search for a solution (offline tool).
function Tricks.findSolution(trick: TrickConfig.Trick): PoolPhysics.ShotParams?
	for _, elevation in { 0, 40, 55 } do
		for _, power in { 0.3, 0.45, 0.6, 0.75, 0.9 } do
			for step = 0, 1439 do
				local shot = {
					angle = step / 1440 * 2 * math.pi,
					power = power,
					spinX = 0,
					spinY = 0,
					elevation = math.rad(elevation),
				}
				if Tricks.solved(trick, Tricks.play(trick, shot)) then
					return shot
				end
			end
		end
	end
	return nil
end

return Tricks
