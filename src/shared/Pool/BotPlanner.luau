--!strict
-- Bot shot selection. Pure Luau: randomness and yielding are injected by the caller, so the
-- same code runs on the server (spread over frames) and in Lune tests.
--
-- For every target ball and pocket: aim through the ghost ball, keep the shot if the cue ball
-- reaches the target first and the target's path to the pocket is clear, then try each power and
-- follow/draw variant in the real simulation and score it with the real rules. The best plan is
-- executed with difficulty-dependent noise.

local AimPredictor = require("./AimPredictor")
local Bot = require("../Config/Bot")
local PoolPhysics = require("./PoolPhysics")
local PoolRules = require("./PoolRules")
local Rules = require("../Config/Rules")
local TableGeometry = require("./TableGeometry")

export type Context = {
	geometry: TableGeometry.Geometry,
	balls: { PoolPhysics.BallState },
	rules: PoolRules.RulesState, -- `current` is the bot
	variant: Rules.Variant,
	ballInHand: boolean,
	kitchenOnly: boolean,
}

export type Plan = {
	shot: PoolPhysics.ShotParams,
	calledPocket: number?,
	cueBallPos: { x: number, y: number }?,
	score: number,
}

type Candidate = {
	angle: number,
	cueX: number,
	cueY: number,
	pocket: number,
}

local SCORE_WIN = 1000
local SCORE_FOUL = -200
local SCORE_POT = 100
local SCORE_NEXT_SHOT = 15 -- per own ball the cue ball can reach next

local BotPlanner = {}

local function withCueAt(balls: { PoolPhysics.BallState }, x: number, y: number): { PoolPhysics.BallState }
	local copy = table.clone(balls)
	for i, b in copy do
		if b.id == 0 then
			copy[i] = { id = 0, x = x, y = y, status = "Stationary", qx = b.qx, qy = b.qy, qz = b.qz, qw = b.qw }
		end
	end
	return copy
end

local function targets(ctx: Context): { PoolPhysics.BallState }
	local player = ctx.rules.current
	local group: PoolRules.Group? = ctx.rules.groups[player]
	local cleared = group ~= nil and PoolRules.groupCleared(ctx.balls, group)
	local list = {}
	for _, b in ctx.balls do
		if b.status == "Stationary" and b.id ~= 0 then
			local ok
			if cleared then
				ok = b.id == 8
			elseif group then
				ok = PoolRules.groupOf(b.id) == group
			else
				ok = b.id ~= 8
			end
			if ok then
				table.insert(list, b)
			end
		end
	end
	return list
end

local function pathClear(
	balls: { PoolPhysics.BallState },
	skip: number,
	ax: number,
	ay: number,
	bx: number,
	by: number,
	R: number
): boolean
	local dx, dy = bx - ax, by - ay
	local lengthSq = dx * dx + dy * dy
	for _, b in balls do
		if b.status == "Stationary" and b.id ~= skip and b.id ~= 0 then
			local u = math.clamp(((b.x - ax) * dx + (b.y - ay) * dy) / lengthSq, 0, 1)
			local px, py = ax + dx * u - b.x, ay + dy * u - b.y
			if px * px + py * py < (2 * R) ^ 2 then
				return false
			end
		end
	end
	return true
end

local function candidates(ctx: Context, level: Bot.Level): { Candidate }
	local geometry = ctx.geometry
	local R = geometry.ballRadius
	local cue: PoolPhysics.BallState? = nil
	for _, b in ctx.balls do
		if b.id == 0 then
			cue = b
		end
	end
	assert(cue, "no cue ball")
	local maxCut = math.cos(math.rad(level.MaxCutDegrees))
	local list = {}
	for _, target in targets(ctx) do
		for _, pocket in geometry.pockets do
			local px, py = pocket.x - target.x, pocket.y - target.y
			local distance = math.sqrt(px * px + py * py)
			local dx, dy = px / distance, py / distance
			local gx, gy = target.x - dx * 2 * R, target.y - dy * 2 * R
			local cx, cy = cue.x, cue.y
			if ctx.ballInHand then
				cx, cy = gx - dx * Bot.PlacementDistance, gy - dy * Bot.PlacementDistance
				if not PoolRules.canPlaceCue(geometry, ctx.balls, cx, cy, ctx.kitchenOnly) then
					continue
				end
			end
			local ax, ay = gx - cx, gy - cy
			local aimLength = math.sqrt(ax * ax + ay * ay)
			if aimLength < 1e-6 or (ax * dx + ay * dy) / aimLength < maxCut then
				continue
			end
			if not pathClear(ctx.balls, target.id, target.x, target.y, pocket.x, pocket.y, R) then
				continue
			end
			local angle = math.atan2(ay, ax)
			local aim = AimPredictor.predict(geometry, withCueAt(ctx.balls, cx, cy), angle)
			if aim.kind == "Ball" and aim.targetId == target.id then
				table.insert(list, { angle = angle, cueX = cx, cueY = cy, pocket = pocket.id })
			end
		end
	end
	return list
end

-- No pottable shot: roll the cue ball straight at each target with modest power and keep the
-- least bad outcome (the simulation and rules still score it).
local function safeties(ctx: Context): { Candidate }
	local cue: PoolPhysics.BallState? = nil
	for _, b in ctx.balls do
		if b.id == 0 then
			cue = b
		end
	end
	assert(cue, "no cue ball")
	local list = {}
	for _, target in targets(ctx) do
		for _, offset in { 0, -0.6, 0.6 } do
			local angle = math.atan2(target.y - cue.y, target.x - cue.x)
			local distance = math.sqrt((target.x - cue.x) ^ 2 + (target.y - cue.y) ^ 2)
			local spread = math.asin(math.min(1, ctx.geometry.ballRadius / distance))
			table.insert(list, { angle = angle + offset * spread, cueX = cue.x, cueY = cue.y, pocket = 0 })
		end
	end
	return list
end

-- Own balls the cue ball could hit first from where it stopped: a cheap position score.
local function nextShots(ctx: Context, balls: { PoolPhysics.BallState }, rules: PoolRules.RulesState): number
	local cue: PoolPhysics.BallState? = nil
	for _, b in balls do
		if b.id == 0 and b.status == "Stationary" then
			cue = b
		end
	end
	if not cue then
		return 0
	end
	local nextCtx = table.clone(ctx)
	nextCtx.balls = balls
	nextCtx.rules = rules
	local count = 0
	for _, target in targets(nextCtx) do
		local aim = AimPredictor.predict(ctx.geometry, balls, math.atan2(target.y - cue.y, target.x - cue.x))
		if aim.kind == "Ball" and aim.targetId == target.id then
			count += 1
		end
	end
	return count
end

local function score(ctx: Context, rules: PoolRules.RulesResult, sim: PoolPhysics.SimResult): number
	local me = ctx.rules.current
	if rules.gameOver then
		return if rules.winner == me then SCORE_WIN else -SCORE_WIN
	end
	if rules.foul then
		return SCORE_FOUL
	end
	if rules.nextPlayer ~= me then
		return 0
	end
	local nextRules: PoolRules.RulesState = { current = me, groups = rules.groups, isBreak = false }
	return SCORE_POT + SCORE_NEXT_SHOT * math.min(nextShots(ctx, sim.finalState, nextRules), 4)
end

local function gaussian(random: () -> number): number
	return math.sqrt(-2 * math.log(math.max(random(), 1e-12))) * math.cos(2 * math.pi * random())
end

function BotPlanner.plan(ctx: Context, levelName: string, random: () -> number, yield: (() -> ())?): Plan
	local level = Bot.Levels[levelName]
	assert(level, `unknown bot level {levelName}`)
	local geometry = ctx.geometry

	if ctx.rules.isBreak then
		local cueX, cueY = geometry.headSpotX, 0
		local apex: PoolPhysics.BallState? = nil
		for _, b in ctx.balls do
			if b.id == 1 then
				apex = b
			end
		end
		local angle = if apex then math.atan2(apex.y - cueY, apex.x - cueX) else 0
		return {
			shot = {
				angle = angle + math.rad(level.AngleNoiseDegrees) * gaussian(random),
				power = level.BreakPower,
				spinX = 0,
				spinY = 0,
				elevation = 0,
			},
			cueBallPos = if ctx.ballInHand then { x = cueX, y = cueY } else nil,
			score = 0,
		}
	end

	local list = candidates(ctx, level)
	local powers, spins = level.Powers, level.SpinsY
	if #list == 0 then
		list = safeties(ctx)
		powers, spins = { 0.3 }, { 0 }
	end

	local best: Plan? = nil
	for _, candidate in list do
		local balls = withCueAt(ctx.balls, candidate.cueX, candidate.cueY)
		local calledPocket = if candidate.pocket > 0 then candidate.pocket else nil
		for _, power in powers do
			for _, spinY in spins do
				local shot = { angle = candidate.angle, power = power, spinX = 0, spinY = spinY, elevation = 0 }
				local sim = PoolPhysics.simulateShot({ geometry = geometry, balls = balls }, shot, { record = false })
				local outcome = PoolRules.evaluate(ctx.rules, ctx.variant, sim, { calledPocket = calledPocket })
				local value = score(ctx, outcome, sim)
				if not best or value > best.score then
					best = {
						shot = shot,
						calledPocket = calledPocket,
						cueBallPos = if ctx.ballInHand then { x = candidate.cueX, y = candidate.cueY } else nil,
						score = value,
					}
				end
				if yield then
					yield()
				end
			end
		end
	end

	local chosen: Plan = best
		or {
			shot = { angle = random() * 2 * math.pi, power = 0.3, spinX = 0, spinY = 0, elevation = 0 },
			calledPocket = nil,
			cueBallPos = nil,
			score = SCORE_FOUL,
		}
	local shot = chosen.shot
	chosen.shot = {
		angle = shot.angle + math.rad(level.AngleNoiseDegrees) * gaussian(random),
		power = math.clamp(shot.power * (1 + level.PowerNoise * gaussian(random)), 0.05, 1),
		spinX = shot.spinX,
		spinY = shot.spinY,
		elevation = shot.elevation,
	}
	return chosen
end

return BotPlanner
