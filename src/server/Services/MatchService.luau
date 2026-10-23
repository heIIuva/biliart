--!strict
-- Matches against the bot: turns, turn timer, ball in hand, called pocket for the 8, end of the
-- match. The server simulates every shot and applies PoolRules; clients only send intents.
-- Leaving after the first shot loses the match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local BotPlanner = require(Shared.Pool.BotPlanner)
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local PoolRules = require(Shared.Pool.PoolRules)
local Rack = require(Shared.Pool.Rack)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Rules = require(Shared.Config.Rules)
local TrajectoryCodec = require(Shared.Pool.TrajectoryCodec)
local Validate = require(Shared.Util.Validate)
local BotService = require(script.Parent.BotService)
local TableService = require(script.Parent.TableService)

local PLAYBACK_GRACE = 0.6 -- seconds after a trajectory ends before the next turn starts
local LATE_SHOT_GRACE = 0.5 -- accept a shot this long after the turn timer (network delay)

type Seat = {
	player: Player?,
	level: string?, -- bot level; nil for a human
	name: string,
	userId: number,
	timeouts: number,
}

type Match = {
	entry: TableService.Entry,
	seats: { Seat },
	rules: PoolRules.RulesState,
	variant: Rules.Variant,
	phase: "Playing" | "Over",
	ballInHand: boolean,
	kitchenOnly: boolean,
	turn: number, -- increments every turn; stale timers and bot plans compare it
	turnEndsAt: number,
	busy: boolean, -- a shot is playing back
	started: boolean, -- the first shot was taken
	reasonKey: string?,
	winner: number?,
}

local matches: { [string]: Match } = {}
local shotLimiter = RateLimiter.new(1, 2)
local startLimiter = RateLimiter.new(0.5, 2)

local function snapshot(entry: TableService.Entry): Remotes.MatchSnapshot
	local match = matches[entry.id]
	if not match then
		return {
			tableId = entry.id,
			phase = "Idle",
			players = {},
			current = 1,
			isBreak = false,
			ballInHand = false,
			kitchenOnly = false,
			mustCall = false,
			turnEndsAt = 0,
		}
	end
	local players: { Remotes.MatchPlayer } = {}
	for i, seat in match.seats do
		table.insert(players, {
			name = seat.name,
			userId = seat.userId,
			isBot = seat.level ~= nil,
			group = match.rules.groups[i] :: string?,
		})
	end
	return {
		tableId = entry.id,
		phase = match.phase,
		players = players,
		current = match.rules.current,
		isBreak = match.rules.isBreak,
		ballInHand = match.ballInHand,
		kitchenOnly = match.kitchenOnly,
		mustCall = PoolRules.mustCallPocket(match.rules, entry.balls, match.rules.current),
		turnEndsAt = match.turnEndsAt,
		reasonKey = match.reasonKey,
		winner = match.winner,
	}
end

local function broadcast(entry: TableService.Entry)
	Remotes.Event("MatchState"):FireAllClients(snapshot(entry))
end

local function turnSeconds(seat: Seat): number
	return math.max(Rules.MinTurnSeconds, Rules.TurnSeconds - seat.timeouts * Rules.TimeoutPenaltySeconds)
end

local function findBall(balls: { PoolPhysics.BallState }, id: number): PoolPhysics.BallState?
	for _, b in balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local playShot: (Match, PoolPhysics.ShotParams, number?, { x: number, y: number }?) -> ()
local startTurn: (Match) -> ()

local function finish(match: Match, winner: number, reasonKey: string)
	match.phase = "Over"
	match.winner = winner
	match.reasonKey = reasonKey
	match.turn += 1
	broadcast(match.entry)
end

local function onTimeout(match: Match, turn: number)
	if matches[match.entry.id] ~= match or match.turn ~= turn or match.busy or match.phase ~= "Playing" then
		return
	end
	local outcome = PoolRules.timeout(match.rules)
	match.seats[match.rules.current].timeouts += 1
	match.rules = { current = outcome.nextPlayer, groups = outcome.groups, isBreak = match.rules.isBreak }
	match.ballInHand = true
	match.kitchenOnly = match.rules.isBreak and match.variant.BreakFromKitchen
	match.reasonKey = outcome.reasonKey
	startTurn(match)
end

function startTurn(match: Match)
	local entry = match.entry
	match.turn += 1
	-- Ball in hand with the cue ball gone: show it on the head spot for the player to move.
	local cue = findBall(entry.balls, 0)
	if match.ballInHand and cue and cue.status ~= "Stationary" then
		Rack.placeFree(entry.geometry, entry.balls, cue, entry.geometry.headSpotX, 0, -entry.geometry.ballRadius)
		TableService.setBalls(entry, entry.balls, true)
	end
	local seat = match.seats[match.rules.current]
	local seconds = turnSeconds(seat)
	match.turnEndsAt = Workspace:GetServerTimeNow() + seconds
	broadcast(entry)

	local turn = match.turn
	local level = seat.level
	if level then
		local ctx: BotPlanner.Context = {
			geometry = entry.geometry,
			balls = table.clone(entry.balls),
			rules = match.rules,
			variant = match.variant,
			ballInHand = match.ballInHand,
			kitchenOnly = match.kitchenOnly,
		}
		task.spawn(BotService.takeTurn, ctx, level, function()
			return matches[entry.id] == match and match.turn == turn and not match.busy
		end, function(plan: BotPlanner.Plan)
			local pos: { x: number, y: number }? = plan.cueBallPos
			if pos and not PoolRules.canPlaceCue(entry.geometry, entry.balls, pos.x, pos.y, match.kitchenOnly) then
				pos = nil
			end
			playShot(match, plan.shot, plan.calledPocket, pos)
		end)
	else
		task.delay(seconds, onTimeout, match, turn)
	end
end

function playShot(
	match: Match,
	shot: PoolPhysics.ShotParams,
	calledPocket: number?,
	cueBallPos: { x: number, y: number }?
)
	local entry = match.entry
	local balls = table.clone(entry.balls)
	if cueBallPos then
		for i, b in balls do
			if b.id == 0 then
				balls[i] = {
					id = 0,
					x = cueBallPos.x,
					y = cueBallPos.y,
					status = "Stationary",
					qx = b.qx,
					qy = b.qy,
					qz = b.qz,
					qw = b.qw,
				}
			end
		end
	end
	match.busy = true
	match.started = true
	local sim = PoolPhysics.simulateShot({ geometry = entry.geometry, balls = balls }, shot)
	local outcome = PoolRules.evaluate(match.rules, match.variant, sim, { calledPocket = calledPocket })
	local final = sim.finalState
	local eight = findBall(final, 8)
	if outcome.respotEight and eight then
		Rack.placeFree(entry.geometry, final, eight, entry.geometry.footSpotX, 0, entry.geometry.ballRadius)
	end
	TableService.setBalls(entry, final, false)
	local message: Remotes.ShotResultPayload = {
		tableId = entry.id,
		trajectory = TrajectoryCodec.encode(sim),
		balls = final,
	}
	-- ponytail: every client gets every table's shots; limit to nearby players when tables multiply (phase 7).
	Remotes.Event("ShotResult"):FireAllClients(message)

	match.rules = { current = outcome.nextPlayer, groups = outcome.groups, isBreak = false }
	match.ballInHand = outcome.ballInHand
	match.kitchenOnly = false
	match.reasonKey = outcome.reasonKey
	local turn = match.turn
	task.delay(sim.duration + PLAYBACK_GRACE, function()
		if matches[entry.id] ~= match or match.turn ~= turn then
			return
		end
		match.busy = false
		if outcome.gameOver then
			finish(match, outcome.winner :: number, outcome.reasonKey)
		else
			startTurn(match)
		end
	end)
end

local function onShot(player: Player, payload: unknown)
	if not shotLimiter:Allow(player) then
		return
	end
	local entry = TableService.tableOf(player)
	local match = if entry then matches[entry.id] else nil
	if not entry or not match or match.phase ~= "Playing" or match.busy then
		return
	end
	if match.seats[match.rules.current].player ~= player then
		return
	end
	if Workspace:GetServerTimeNow() > match.turnEndsAt + LATE_SHOT_GRACE then
		return
	end
	local shot = Validate.shotParams(payload)
	if not shot then
		return
	end
	local raw = payload :: { [unknown]: unknown }
	local calledPocket = Validate.pocket(raw.calledPocket)
	if PoolRules.mustCallPocket(match.rules, entry.balls, match.rules.current) and not calledPocket then
		return
	end
	local cueBallPos = nil
	if match.ballInHand and raw.cueBallPos ~= nil then
		local point = Validate.point(raw.cueBallPos)
		if not point or not PoolRules.canPlaceCue(entry.geometry, entry.balls, point.x, point.y, match.kitchenOnly) then
			return
		end
		cueBallPos = point
	end
	playShot(match, shot, calledPocket, cueBallPos)
end

local function onStart(player: Player, payload: unknown)
	local level = Validate.botLevel(payload)
	local entry = TableService.tableOf(player)
	if not startLimiter:Allow(player) or not level or not entry then
		return
	end
	local existing = matches[entry.id]
	if existing and existing.phase == "Playing" then
		return
	end
	TableService.rack(entry)
	local variant = Rules.Variants[entry.variant]
	local match: Match = {
		entry = entry,
		seats = {
			{ player = player, level = nil, name = player.DisplayName, userId = player.UserId, timeouts = 0 },
			{ player = nil, level = level, name = `BOT_{string.upper(level)}`, userId = 0, timeouts = 0 },
		},
		rules = { current = 1, groups = {}, isBreak = true },
		variant = variant,
		phase = "Playing",
		ballInHand = true,
		kitchenOnly = variant.BreakFromKitchen,
		turn = 0,
		turnEndsAt = 0,
		busy = false,
		started = false,
		reasonKey = nil,
		winner = nil,
	}
	matches[entry.id] = match
	startTurn(match)
end

local function onUnseated(_player: Player, entry: TableService.Entry)
	local match = matches[entry.id]
	if match then
		match.turn += 1 -- invalidates timers and a thinking bot
		if match.phase == "Playing" and match.started then
			-- ponytail: the loss is only announced; results are recorded with player data (phase 6).
			finish(match, 2, "RULE_LOSS_LEFT")
		end
		matches[entry.id] = nil
	end
	broadcast(entry)
end

local MatchService = {}

function MatchService.Start()
	Remotes.Event("Shot").OnServerEvent:Connect(onShot)
	Remotes.Event("StartMatch").OnServerEvent:Connect(onStart)
	TableService.Seated:Connect(function(_, entry)
		broadcast(entry)
	end)
	TableService.Unseated:Connect(onUnseated)
	Players.PlayerRemoving:Connect(function(player)
		shotLimiter:Forget(player)
		startLimiter:Forget(player)
	end)
end

return MatchService
