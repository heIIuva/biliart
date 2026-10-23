--!strict
-- Everything notable about one shot, built from the simulation and the rules outcome (GDD 7.1).
-- The classifier matches titles against these fields. Pure Luau: no Roblox API.

local AimPredictor = require("./AimPredictor")
local Hype = require("../Config/Hype")
local Physics = require("../Config/Physics")
local PoolPhysics = require("./PoolPhysics")
local PoolRules = require("./PoolRules")
local TableGeometry = require("./TableGeometry")

export type Report = {
	isBreak: boolean,
	power: number,
	cueSpeed: number,
	spinX: number,
	spinY: number,
	elevation: number,
	potted: number, -- object balls potted (the 8 included)
	pottedOwn: number, -- of the shooter's group (after this shot's group assignment)
	pottedEight: boolean,
	firstContact: number, -- first ball the cue ball hit, 0 if none
	cushionsBeforePot: number, -- most cushions any potted ball touched before dropping
	potDistance: number, -- longest path of a potted ball (meters)
	cueAirborne: boolean,
	jumpedOverBall: boolean,
	curved: boolean,
	cleared: boolean, -- the whole group and the 8 in one visit
	foul: string, -- "" when the shot was legal
	rattled: boolean, -- an object ball hit the jaws slowly and stayed out
	missedEverything: boolean,
	cueScratched: boolean,
	cueOffTable: boolean,
	snookeredOpponent: boolean, -- the opponent has no direct line to any of their balls
	turnStreak: number, -- shots in this visit, this one included
	won: boolean,
	lostByEight: boolean,
	eightOnBreak: boolean,
}

export type Input = {
	sim: PoolPhysics.SimResult,
	shot: PoolPhysics.ShotParams,
	before: PoolRules.RulesState, -- rules state the shot was taken in
	outcome: PoolRules.RulesResult,
	ballsBefore: { PoolPhysics.BallState },
	geometry: TableGeometry.Geometry,
	visitOwnPots: number, -- own balls potted earlier in this visit
	turnStreak: number,
}

local Kind = PoolPhysics.EventKind

local ShotReport = {}

local function overJump(jumps: { PoolPhysics.Jump }, balls: { PoolPhysics.BallState }, R: number): boolean
	for _, jump in jumps do
		local dx, dy = jump.x1 - jump.x0, jump.y1 - jump.y0
		local lengthSq = dx * dx + dy * dy
		if lengthSq > 1e-8 then
			for _, b in balls do
				if b.id ~= 0 and b.status == "Stationary" then
					local u = ((b.x - jump.x0) * dx + (b.y - jump.y0) * dy) / lengthSq
					if u > 0 and u < 1 then
						local px, py = jump.x0 + dx * u - b.x, jump.y0 + dy * u - b.y
						if px * px + py * py < (2 * R) ^ 2 then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

-- No straight line from the cue ball to the center of any ball the player may hit first.
local function snookered(
	geometry: TableGeometry.Geometry,
	balls: { PoolPhysics.BallState },
	rules: PoolRules.RulesState,
	player: number
): boolean
	local cue: PoolPhysics.BallState? = nil
	for _, b in balls do
		if b.id == 0 and b.status == "Stationary" then
			cue = b
		end
	end
	if not cue then
		return false
	end
	local group: PoolRules.Group? = rules.groups[player]
	local cleared = group ~= nil and PoolRules.groupCleared(balls, group)
	for _, b in balls do
		local eligible
		if cleared then
			eligible = b.id == 8
		elseif group then
			eligible = PoolRules.groupOf(b.id) == group
		else
			eligible = b.id ~= 8 and b.id ~= 0
		end
		if eligible and b.status == "Stationary" then
			local aim = AimPredictor.predict(geometry, balls, math.atan2(b.y - cue.y, b.x - cue.x))
			if aim.kind == "Ball" and aim.targetId == b.id then
				return false
			end
		end
	end
	return true
end

function ShotReport.build(input: Input): Report
	local sim, outcome, before = input.sim, input.outcome, input.before
	local shooter = before.current
	local ownGroup: PoolRules.Group? = outcome.groups[shooter]

	local potted, pottedOwn, pottedEight = 0, 0, false
	local firstContact = 0
	local cushionsByBall: { [number]: number } = {}
	local cushionsBeforePot, potDistance = 0, 0
	local cueScratched, cueOffTable, cueAirborne = false, false, false
	local rattledBalls: { [number]: boolean } = {}
	for _, e in sim.events do
		local kind = e.kind
		if kind == Kind.BallBall and firstContact == 0 and (e.a == 0 or e.b == 0) then
			firstContact = if e.a == 0 then e.b else e.a
		elseif kind == Kind.BallCushion or kind == Kind.BallJaw then
			cushionsByBall[e.a] = (cushionsByBall[e.a] or 0) + 1
		elseif kind == Kind.Rattle and e.a ~= 0 then
			rattledBalls[e.a] = true
		elseif kind == Kind.Airborne and e.a == 0 then
			cueAirborne = true
		elseif kind == Kind.Pocketed then
			if e.a == 0 then
				cueScratched = true
			else
				potted += 1
				pottedEight = pottedEight or e.a == 8
				if ownGroup and PoolRules.groupOf(e.a) == ownGroup then
					pottedOwn += 1
				end
				cushionsBeforePot = math.max(cushionsBeforePot, cushionsByBall[e.a] or 0)
				potDistance = math.max(potDistance, sim.travel[e.a] or 0)
			end
		elseif kind == Kind.OffTable and e.a == 0 then
			cueOffTable = true
		end
	end

	local rattled = false
	for _, b in sim.finalState do
		if rattledBalls[b.id] and b.status == "Stationary" then
			rattled = true
		end
	end

	local won = outcome.gameOver and outcome.winner == shooter
	local passes = not outcome.gameOver and not outcome.foul and outcome.nextPlayer ~= shooter
	local nextRules: PoolRules.RulesState = { current = 3 - shooter, groups = outcome.groups, isBreak = false }

	return {
		isBreak = before.isBreak,
		power = input.shot.power,
		cueSpeed = input.shot.power * Physics.MaxCueSpeed,
		spinX = input.shot.spinX,
		spinY = input.shot.spinY,
		elevation = input.shot.elevation,
		potted = potted,
		pottedOwn = pottedOwn,
		pottedEight = pottedEight,
		firstContact = firstContact,
		cushionsBeforePot = cushionsBeforePot,
		potDistance = potDistance,
		cueAirborne = cueAirborne,
		jumpedOverBall = cueAirborne and overJump(sim.cueJumps, input.ballsBefore, input.geometry.ballRadius),
		curved = input.shot.elevation >= Hype.CurveMinElevation and sim.cueCurve >= Hype.CurveMinDrift,
		cleared = won and not before.isBreak and input.visitOwnPots + pottedOwn >= 7,
		foul = outcome.foul or "",
		rattled = rattled,
		missedEverything = firstContact == 0,
		cueScratched = cueScratched,
		cueOffTable = cueOffTable,
		snookeredOpponent = passes and snookered(input.geometry, sim.finalState, nextRules, 3 - shooter),
		turnStreak = input.turnStreak,
		won = won,
		lostByEight = outcome.gameOver and outcome.winner ~= shooter and pottedEight,
		eightOnBreak = won and before.isBreak,
	}
end

return ShotReport
