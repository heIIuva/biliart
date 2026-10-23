--!strict
-- 8-ball rules: table of scenarios built from synthetic simulation events.
local PoolPhysics = require("../src/shared/Pool/PoolPhysics")
local PoolRules = require("../src/shared/Pool/PoolRules")
local Rack = require("../src/shared/Pool/Rack")
local Rules = require("../src/shared/Config/Rules")
local TableGeometry = require("../src/shared/Pool/TableGeometry")

local K = PoolPhysics.EventKind
local RULES = Rules.Variants.Standard
local SOLIDS = { 1, 2, 3, 4, 5, 6, 7 }

-- events: { kind, a, b }; gone: balls already off the table before the shot.
local function sim(events: { { number } }, gone: { number }?): PoolPhysics.SimResult
	local finalState: { PoolPhysics.BallState } = {}
	for id = 0, 15 do
		table.insert(finalState, { id = id, x = 0, y = 0, status = "Stationary" })
	end
	for _, id in gone or {} do
		finalState[id + 1].status = "Pocketed"
	end
	local list: { PoolPhysics.Event } = {}
	for i, e in events do
		table.insert(list, { t = i * 0.01, kind = e[1], a = e[2], b = e[3] or 0, speed = 1 })
		if e[1] == K.Pocketed then
			finalState[e[2] + 1].status = "Pocketed"
		elseif e[1] == K.OffTable then
			finalState[e[2] + 1].status = "OffTable"
		end
	end
	return {
		finalState = finalState,
		events = list,
		frames = {},
		recordHz = 60,
		duration = 1,
		travel = {},
		cueCurve = 0,
		cueJumps = {},
	}
end

local function state(groups: { [number]: PoolRules.Group }?, isBreak: boolean?): PoolRules.RulesState
	return { current = 1, groups = groups or {}, isBreak = isBreak or false }
end

local SOLIDS_P1: { [number]: PoolRules.Group } = { [1] = "Solids", [2] = "Stripes" }

type Expect = {
	foul: string?,
	next: number?,
	inHand: boolean?,
	over: boolean?,
	winner: number?,
	group: string?,
	respot: boolean?,
}

local function expect(r: PoolRules.RulesResult, e: Expect)
	assert(r.foul == e.foul, `foul: expected {e.foul}, got {r.foul}`)
	if e.next then
		assert(r.nextPlayer == e.next, `next: expected {e.next}, got {r.nextPlayer}`)
	end
	if e.inHand ~= nil then
		assert(r.ballInHand == e.inHand, `ballInHand: expected {e.inHand}`)
	end
	assert(r.gameOver == (e.over or false), `gameOver: expected {e.over}`)
	if e.winner then
		assert(r.winner == e.winner, `winner: expected {e.winner}, got {r.winner}`)
	end
	if e.group then
		assert(r.groups[1] == e.group, `group of player 1: expected {e.group}, got {r.groups[1]}`)
	end
	if e.respot ~= nil then
		assert(r.respotEight == e.respot, `respotEight: expected {e.respot}`)
	end
	assert(type(r.reasonKey) == "string" and #r.reasonKey > 0, "reason key")
end

local function evaluate(s: PoolRules.RulesState, result: PoolPhysics.SimResult, called: number?): PoolRules.RulesResult
	return PoolRules.evaluate(s, RULES, result, { calledPocket = called })
end

local hitRail = { K.BallCushion, 3, 1 }

return {
	-- Break
	["break: pot keeps the turn, table stays open"] = function()
		local r = evaluate(state(nil, true), sim({ { K.BallBall, 0, 1 }, { K.Pocketed, 3, 6 } }))
		expect(r, { next = 1, inHand = false })
		assert(r.groups[1] == nil, "table must stay open after the break")
	end,
	["break: 4 balls to cushions is legal, turn passes"] = function()
		local r = evaluate(
			state(nil, true),
			sim({
				{ K.BallBall, 0, 1 },
				{ K.BallCushion, 2, 1 },
				{ K.BallCushion, 3, 2 },
				{ K.BallCushion, 4, 3 },
				{
					K.BallJaw,
					5,
					6,
				},
			})
		)
		expect(r, { next = 2, inHand = false })
	end,
	["break: 3 balls to cushions is an illegal break"] = function()
		local r = evaluate(
			state(nil, true),
			sim({ { K.BallBall, 0, 1 }, { K.BallCushion, 2, 1 }, { K.BallCushion, 3, 2 }, { K.BallCushion, 3, 3 } })
		)
		expect(r, { foul = "IllegalBreak", next = 2, inHand = true })
	end,
	["break: scratch is a foul even with a pot"] = function()
		local r = evaluate(state(nil, true), sim({ { K.BallBall, 0, 1 }, { K.Pocketed, 2, 1 }, { K.Pocketed, 0, 3 } }))
		expect(r, { foul = "CueScratch", next = 2, inHand = true })
	end,
	["break: 8 in wins"] = function()
		local r = evaluate(state(nil, true), sim({ { K.BallBall, 0, 1 }, { K.Pocketed, 8, 2 } }))
		expect(r, { over = true, winner = 1 })
	end,
	["break: 8 in with a scratch is respotted, not a win"] = function()
		local r = evaluate(state(nil, true), sim({ { K.BallBall, 0, 1 }, { K.Pocketed, 8, 2 }, { K.Pocketed, 0, 4 } }))
		expect(r, { foul = "CueScratch", next = 2, respot = true })
	end,

	-- Open table
	["open table: first pot assigns groups"] = function()
		local r = evaluate(state(), sim({ { K.BallBall, 0, 9 }, { K.Pocketed, 3, 2 }, { K.Pocketed, 12, 5 } }))
		expect(r, { next = 1, group = "Solids" })
		assert(r.groups[2] == "Stripes", "opponent gets the other group")
	end,
	["open table: first potted stripe gives stripes"] = function()
		local r = evaluate(state(), sim({ { K.BallBall, 0, 2 }, { K.Pocketed, 10, 6 }, { K.Pocketed, 1, 1 } }))
		expect(r, { next = 1, group = "Stripes" })
	end,
	["open table: hitting the 8 first is a foul"] = function()
		local r = evaluate(state(), sim({ { K.BallBall, 0, 8 }, hitRail }))
		expect(r, { foul = "WrongBallFirst", next = 2, inHand = true })
	end,
	["open table: legal miss passes the turn, groups stay open"] = function()
		local r = evaluate(state(), sim({ { K.BallBall, 0, 4 }, hitRail }))
		expect(r, { next = 2, inHand = false })
		assert(r.groups[1] == nil, "still open")
	end,

	-- Groups assigned
	["groups: opponent ball first is a foul"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 11 }, hitRail })),
			{ foul = "WrongBallFirst", next = 2, inHand = true }
		)
	end,
	["groups: missing every ball is a foul"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallCushion, 0, 2 } })),
			{ foul = "NoContact", next = 2, inHand = true }
		)
	end,
	["groups: no rail after contact and no pot is a foul"] = function()
		expect(evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 2 } })), { foul = "NoRail", next = 2, inHand = true })
	end,
	["groups: rail before contact does not count"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallCushion, 0, 4 }, { K.BallBall, 0, 2 } })),
			{ foul = "NoRail", next = 2 }
		)
	end,
	["groups: contact and rail, no pot passes the turn"] = function()
		expect(evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 2 }, hitRail })), { next = 2, inHand = false })
	end,
	["groups: potting only an opponent ball passes the turn"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 2 }, { K.BallBall, 2, 9 }, { K.Pocketed, 9, 3 } })),
			{ next = 2, inHand = false }
		)
	end,
	["groups: potting an own ball keeps the turn"] = function()
		expect(evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 2 }, { K.Pocketed, 2, 3 } })), { next = 1 })
	end,
	["groups: scratch while potting an own ball is a foul"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 2 }, { K.Pocketed, 2, 3 }, { K.Pocketed, 0, 1 } })),
			{ foul = "CueScratch", next = 2, inHand = true }
		)
	end,
	["groups: cue ball off the table is a foul"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 2 }, hitRail, { K.OffTable, 0 } })),
			{ foul = "CueOffTable", next = 2, inHand = true }
		)
	end,
	["timeout gives the opponent ball in hand"] = function()
		local r = PoolRules.timeout(state(SOLIDS_P1))
		expect(r, { foul = "Timeout", next = 2, inHand = true })
	end,

	-- The 8
	["8: potted before the group is cleared loses"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 2 }, { K.BallBall, 2, 8 }, { K.Pocketed, 8, 1 } }), 1),
			{ over = true, winner = 2 }
		)
	end,
	["8: last own ball and the 8 together loses"] = function()
		local gone = { 1, 2, 3, 4, 5, 6 }
		expect(
			evaluate(
				state(SOLIDS_P1),
				sim({ { K.BallBall, 0, 7 }, { K.Pocketed, 7, 2 }, { K.Pocketed, 8, 3 } }, gone),
				3
			),
			{ over = true, winner = 2 }
		)
	end,
	["8: called pocket after clearing wins"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 8 }, { K.Pocketed, 8, 4 } }, SOLIDS), 4),
			{ over = true, winner = 1 }
		)
	end,
	["8: wrong pocket loses"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 8 }, { K.Pocketed, 8, 4 } }, SOLIDS), 6),
			{ over = true, winner = 2 }
		)
	end,
	["8: no called pocket loses"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 8 }, { K.Pocketed, 8, 4 } }, SOLIDS), nil),
			{ over = true, winner = 2 }
		)
	end,
	["8: pot with a scratch loses"] = function()
		expect(
			evaluate(
				state(SOLIDS_P1),
				sim({ { K.BallBall, 0, 8 }, { K.Pocketed, 8, 4 }, { K.Pocketed, 0, 2 } }, SOLIDS),
				4
			),
			{ foul = "CueScratch", over = true, winner = 2 }
		)
	end,
	["8: off the table loses"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 8 }, { K.OffTable, 8 } }, SOLIDS), 4),
			{ over = true, winner = 2 }
		)
	end,
	["8: after clearing, hitting another ball first is a foul"] = function()
		expect(
			evaluate(state(SOLIDS_P1), sim({ { K.BallBall, 0, 12 }, hitRail }, SOLIDS)),
			{ foul = "WrongBallFirst", next = 2, inHand = true }
		)
	end,
	["8: must call a pocket only after clearing"] = function()
		local s = state(SOLIDS_P1)
		assert(not PoolRules.mustCallPocket(s, sim({}).finalState, 1), "group not cleared yet")
		assert(PoolRules.mustCallPocket(s, sim({}, SOLIDS).finalState, 1), "group cleared")
		assert(not PoolRules.mustCallPocket(state(), sim({}, SOLIDS).finalState, 1), "open table never calls")
	end,

	-- Ball in hand and respot
	["ball in hand: placement must be inside, free and in the kitchen when required"] = function()
		local geo = TableGeometry.get("Standard")
		local balls = Rack.eightBall(geo, 1)
		local R = geo.ballRadius
		assert(PoolRules.canPlaceCue(geo, balls, -0.6, 0.2, true), "free kitchen spot")
		assert(not PoolRules.canPlaceCue(geo, balls, 0.3, 0, true), "outside the kitchen")
		assert(PoolRules.canPlaceCue(geo, balls, 0.3, 0, false), "anywhere when not restricted")
		assert(not PoolRules.canPlaceCue(geo, balls, balls[2].x + R, balls[2].y, false), "overlapping a ball")
		assert(not PoolRules.canPlaceCue(geo, balls, geo.halfLength, 0, false), "inside the cushion")
	end,
	["respot: the 8 goes to the foot spot or behind it"] = function()
		local geo = TableGeometry.get("Standard")
		local balls: { PoolPhysics.BallState } = {
			{ id = 1, x = geo.footSpotX, y = 0, status = "Stationary" },
			{ id = 8, x = 0, y = 0, status = "Pocketed" },
		}
		assert(Rack.placeFree(geo, balls, balls[2], geo.footSpotX, 0, geo.ballRadius), "spot found")
		assert(balls[2].status == "Stationary", "back on the table")
		assert(balls[2].x >= geo.footSpotX + 2 * geo.ballRadius - 1e-9, "moved past the occupied foot spot")
	end,
}
