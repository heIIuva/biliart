--!strict
local BotPlanner = require("../src/shared/Pool/BotPlanner")
local PoolPhysics = require("../src/shared/Pool/PoolPhysics")
local PoolRules = require("../src/shared/Pool/PoolRules")
local Rack = require("../src/shared/Pool/Rack")
local Rules = require("../src/shared/Config/Rules")
local TableGeometry = require("../src/shared/Pool/TableGeometry")

local geo = TableGeometry.get("Standard")
local HL, HW = geo.halfLength, geo.halfWidth
local RULES = Rules.Variants.Standard

-- r = 0.25 makes the Box-Muller noise exactly zero: these tests check the plan, not the aim error.
local function noNoise(): number
	return 0.25
end

local function balls(list: { { number } }): { PoolPhysics.BallState }
	local out: { PoolPhysics.BallState } = {}
	for _, b in list do
		table.insert(out, { id = b[1], x = b[2], y = b[3], status = if b[4] == 1 then "Pocketed" else "Stationary" })
	end
	return out
end

local function context(
	set: { PoolPhysics.BallState },
	groups: { [number]: PoolRules.Group }?,
	inHand: boolean?
): BotPlanner.Context
	return {
		geometry = geo,
		balls = set,
		rules = { current = 1, groups = groups or {}, isBreak = false },
		variant = RULES,
		ballInHand = inHand or false,
		kitchenOnly = false,
	}
end

local function play(ctx: BotPlanner.Context, plan: BotPlanner.Plan): (PoolPhysics.SimResult, PoolRules.RulesResult)
	local set = ctx.balls
	if plan.cueBallPos then
		set = table.clone(set)
		for i, b in set do
			if b.id == 0 then
				set[i] = { id = 0, x = plan.cueBallPos.x, y = plan.cueBallPos.y, status = "Stationary" }
			end
		end
	end
	local sim = PoolPhysics.simulateShot({ geometry = geo, balls = set }, plan.shot)
	return sim, PoolRules.evaluate(ctx.rules, RULES, sim, { calledPocket = plan.calledPocket })
end

return {
	["bot pots an easy ball without a foul"] = function()
		local ctx = context(balls({ { 0, -0.3, 0.1 }, { 1, HL - 0.25, HW - 0.25 }, { 9, -0.8, -0.4 }, { 8, 0, -0.3 } }))
		local plan = BotPlanner.plan(ctx, "Hard", noNoise)
		local _, outcome = play(ctx, plan)
		assert(not outcome.foul, `foul {outcome.foul}`)
		assert(outcome.nextPlayer == 1, `bot should keep the turn ({outcome.reasonKey})`)
	end,

	["bot on the 8 calls the pocket it pots into and wins"] = function()
		local set = balls({ { 0, 0.2, -0.1 }, { 8, HL - 0.3, -HW + 0.3 }, { 9, -0.5, 0.3 } })
		for id = 1, 7 do
			table.insert(set, { id = id, x = 0, y = 0, status = "Pocketed" })
		end
		local ctx = context(set, { [1] = "Solids", [2] = "Stripes" })
		local plan = BotPlanner.plan(ctx, "Hard", noNoise)
		assert(plan.calledPocket, "must call a pocket on the 8")
		local _, outcome = play(ctx, plan)
		assert(outcome.gameOver and outcome.winner == 1, `expected a win, got {outcome.reasonKey}`)
	end,

	["ball in hand: bot places the cue ball legally"] = function()
		local ctx = context(balls({ { 0, -0.5, 0 }, { 3, 0.2, 0.2 }, { 12, 0.6, -0.3 }, { 8, -0.2, -0.3 } }), nil, true)
		local plan = BotPlanner.plan(ctx, "Medium", noNoise)
		local pos = plan.cueBallPos
		assert(pos, "should place the cue ball")
		assert(PoolRules.canPlaceCue(geo, ctx.balls, pos.x, pos.y, false), "illegal placement")
	end,

	["snookered: bot still returns a shot"] = function()
		-- Cue ball boxed in by opponent balls; no straight path to a solid.
		local R = geo.ballRadius
		local ctx = context(
			balls({
				{ 0, 0, 0 },
				{ 9, 2.1 * R, 0 },
				{ 10, -2.1 * R, 0 },
				{ 11, 0, 2.1 * R },
				{ 12, 0, -2.1 * R },
				{ 1, 0.8, 0.4 },
			}),
			{ [1] = "Solids", [2] = "Stripes" }
		)
		local plan = BotPlanner.plan(ctx, "Easy", noNoise)
		assert(plan.shot.power > 0, "a shot is returned")
	end,

	["break: bot breaks from the head spot at its break power"] = function()
		local ctx = context(Rack.eightBall(geo, 3), nil, true)
		ctx.rules.isBreak = true
		local plan = BotPlanner.plan(ctx, "Hard", noNoise)
		assert(plan.shot.power == 1, "hard bot breaks at full power")
		assert(plan.cueBallPos and plan.cueBallPos.x == geo.headSpotX, "breaks from the head spot")
	end,

	["benchmark: planning time after a break"] = function()
		local rack = Rack.eightBall(geo, 5)
		local sim = PoolPhysics.simulateShot(
			{ geometry = geo, balls = rack },
			{ angle = 0, power = 1, spinX = 0, spinY = 0, elevation = 0 },
			{ record = false }
		)
		for _, level in { "Easy", "Medium", "Hard" } do
			local start = os.clock()
			local yields = 0
			local cue = sim.finalState[1]
			local ctx = context(sim.finalState, nil, cue.status ~= "Stationary")
			if cue.status ~= "Stationary" then
				Rack.placeFree(geo, ctx.balls, cue, geo.headSpotX, 0, -geo.ballRadius)
			end
			BotPlanner.plan(ctx, level, math.random, function()
				yields += 1
			end)
			print(string.format("  bot %s: %.0f ms, %d simulations", level, (os.clock() - start) * 1000, yields))
		end
	end,
}
