--!strict
-- 8-ball rules as pure functions over a simulation result: fouls, groups, who shoots next,
-- ball in hand, game over. Pure Luau: no Roblox API.
--
-- Our version (GDD 6): any foul gives the opponent ball in hand anywhere; an illegal break is a
-- foul (no re-rack); the table stays open until the first legal pot after the break; the 8 must
-- go into the called pocket after the shooter's group is cleared.

local PoolPhysics = require("./PoolPhysics")
local Rules = require("../Config/Rules")
local TableGeometry = require("./TableGeometry")

export type Group = "Solids" | "Stripes"

export type Foul = "CueScratch" | "CueOffTable" | "NoContact" | "WrongBallFirst" | "NoRail" | "IllegalBreak" | "Timeout"

export type RulesState = {
	current: number, -- shooting player: 1 or 2
	groups: { [number]: Group }, -- by player; missing = open table
	isBreak: boolean,
}

export type ShotMeta = {
	calledPocket: number?,
}

export type RulesResult = {
	foul: Foul?,
	nextPlayer: number,
	ballInHand: boolean, -- for nextPlayer
	groups: { [number]: Group },
	gameOver: boolean,
	winner: number?,
	respotEight: boolean, -- the 8 left the table on the break: put it back on the foot spot
	reasonKey: string, -- localization key explaining the outcome
}

local Kind = PoolPhysics.EventKind

local FOUL_KEYS: { [Foul]: string } = {
	CueScratch = "RULE_FOUL_SCRATCH",
	CueOffTable = "RULE_FOUL_CUE_OFF_TABLE",
	NoContact = "RULE_FOUL_NO_CONTACT",
	WrongBallFirst = "RULE_FOUL_WRONG_BALL",
	NoRail = "RULE_FOUL_NO_RAIL",
	IllegalBreak = "RULE_FOUL_ILLEGAL_BREAK",
	Timeout = "RULE_FOUL_TIMEOUT",
}

local PoolRules = {}

function PoolRules.groupOf(id: number): Group?
	if id >= 1 and id <= 7 then
		return "Solids"
	elseif id >= 9 and id <= 15 then
		return "Stripes"
	end
	return nil
end

local function otherGroup(group: Group): Group
	return if group == "Solids" then "Stripes" else "Solids"
end

-- True when no ball of `group` is left on the table.
function PoolRules.groupCleared(balls: { PoolPhysics.BallState }, group: Group): boolean
	for _, b in balls do
		if b.status == "Stationary" and PoolRules.groupOf(b.id) == group then
			return false
		end
	end
	return true
end

-- The player must call a pocket before shooting: their group is assigned and cleared.
function PoolRules.mustCallPocket(state: RulesState, balls: { PoolPhysics.BallState }, player: number): boolean
	local group: Group? = state.groups[player]
	return group ~= nil and PoolRules.groupCleared(balls, group)
end

-- Ball in hand: inside the field, not touching another ball, behind the head string if required.
function PoolRules.canPlaceCue(
	geometry: TableGeometry.Geometry,
	balls: { PoolPhysics.BallState },
	x: number,
	y: number,
	kitchenOnly: boolean
): boolean
	local R = geometry.ballRadius
	if math.abs(x) > geometry.halfLength - R or math.abs(y) > geometry.halfWidth - R then
		return false
	end
	if kitchenOnly and x > geometry.headSpotX then
		return false
	end
	for _, b in balls do
		if b.id ~= 0 and b.status == "Stationary" and (b.x - x) ^ 2 + (b.y - y) ^ 2 < (2 * R) ^ 2 then
			return false
		end
	end
	return true
end

local function result(
	state: RulesState,
	groups: { [number]: Group },
	foul: Foul?,
	continues: boolean,
	reasonKey: string
): RulesResult
	local opponent = 3 - state.current
	return {
		foul = foul,
		nextPlayer = if continues and not foul then state.current else opponent,
		ballInHand = foul ~= nil,
		groups = groups,
		gameOver = false,
		winner = nil,
		respotEight = false,
		reasonKey = if foul then FOUL_KEYS[foul] else reasonKey,
	}
end

local function gameOver(
	state: RulesState,
	groups: { [number]: Group },
	winner: number,
	reasonKey: string,
	foul: Foul?
): RulesResult
	return {
		foul = foul,
		nextPlayer = state.current,
		ballInHand = false,
		groups = groups,
		gameOver = true,
		winner = winner,
		respotEight = false,
		reasonKey = reasonKey,
	}
end

function PoolRules.timeout(state: RulesState): RulesResult
	return result(state, table.clone(state.groups), "Timeout", false, "")
end

function PoolRules.evaluate(
	state: RulesState,
	rules: Rules.Variant,
	sim: PoolPhysics.SimResult,
	meta: ShotMeta
): RulesResult
	local shooter, opponent = state.current, 3 - state.current
	local groups = table.clone(state.groups)

	-- Walk the events once.
	local firstContact: number? = nil
	local railAfterContact = false
	local cushionBalls, cushionCount = {}, 0
	local potted: { number } = {}
	local leftTable: { [number]: boolean } = {}
	local cueScratch, cueOff, eightPotted, eightOff = false, false, false, false
	local eightPocket = 0
	for _, e in sim.events do
		local kind = e.kind
		if kind == Kind.BallBall then
			if firstContact == nil and (e.a == 0 or e.b == 0) then
				firstContact = if e.a == 0 then e.b else e.a
			end
		elseif kind == Kind.BallCushion or kind == Kind.BallJaw then
			railAfterContact = railAfterContact or firstContact ~= nil
			if e.a ~= 0 and not cushionBalls[e.a] then
				cushionBalls[e.a] = true
				cushionCount += 1
			end
		elseif kind == Kind.Pocketed then
			leftTable[e.a] = true
			if e.a == 0 then
				cueScratch = true
			elseif e.a == 8 then
				eightPotted, eightPocket = true, e.b
			else
				table.insert(potted, e.a)
			end
		elseif kind == Kind.OffTable then
			leftTable[e.a] = true
			railAfterContact = railAfterContact or firstContact ~= nil -- it went over a rail
			if e.a == 0 then
				cueOff = true
			elseif e.a == 8 then
				eightOff = true
			end
		end
	end

	-- Was the shooter's group already cleared before this shot?
	local shooterGroup = groups[shooter]
	local clearedBefore = false
	if shooterGroup then
		clearedBefore = true
		for _, b in sim.finalState do
			local wasOnTable = b.status == "Stationary" or leftTable[b.id]
			if wasOnTable and PoolRules.groupOf(b.id) == shooterGroup then
				clearedBefore = false
			end
		end
	end

	local foul: Foul? = nil
	if cueOff then
		foul = "CueOffTable"
	elseif cueScratch then
		foul = "CueScratch"
	end

	if state.isBreak then
		local legal = #potted > 0 or eightPotted or cushionCount >= rules.BreakMinCushionBalls
		if not foul and not legal then
			foul = "IllegalBreak"
		end
		if eightPotted and not foul and rules.EightOnBreakWins then
			return gameOver(state, groups, shooter, "RULE_WIN_EIGHT_ON_BREAK", nil)
		end
		local out =
			result(state, groups, foul, #potted > 0, if #potted > 0 then "RULE_CONTINUE" else "RULE_TURN_PASSES")
		out.respotEight = eightPotted or eightOff
		return out
	end

	if not foul then
		if firstContact == nil then
			foul = "NoContact"
		else
			local wrong
			if shooterGroup == nil then
				wrong = firstContact == 8
			elseif clearedBefore then
				wrong = firstContact ~= 8
			else
				wrong = PoolRules.groupOf(firstContact) ~= shooterGroup
			end
			if wrong then
				foul = "WrongBallFirst"
			elseif not railAfterContact and #potted == 0 and not eightPotted then
				foul = "NoRail"
			end
		end
	end

	if eightPotted or eightOff then
		if eightOff then
			return gameOver(state, groups, opponent, "RULE_LOSS_EIGHT_OFF_TABLE", foul)
		elseif not clearedBefore then
			return gameOver(state, groups, opponent, "RULE_LOSS_EIGHT_EARLY", foul)
		elseif foul then
			return gameOver(state, groups, opponent, "RULE_LOSS_EIGHT_FOUL", foul)
		elseif meta.calledPocket ~= eightPocket then
			return gameOver(state, groups, opponent, "RULE_LOSS_EIGHT_WRONG_POCKET", nil)
		end
		return gameOver(state, groups, shooter, "RULE_WIN_EIGHT", nil)
	end

	if foul then
		return result(state, groups, foul, false, "")
	end

	-- Open table: the first legally potted ball decides the groups.
	if shooterGroup == nil and #potted > 0 then
		local group: Group = PoolRules.groupOf(potted[1]) :: Group
		groups[shooter] = group
		groups[opponent] = otherGroup(group)
		return result(state, groups, nil, true, "RULE_GROUP_ASSIGNED")
	end

	for _, id in potted do
		if PoolRules.groupOf(id) == groups[shooter] then
			return result(state, groups, nil, true, "RULE_CONTINUE")
		end
	end
	return result(state, groups, nil, false, "RULE_TURN_PASSES")
end

return PoolRules
