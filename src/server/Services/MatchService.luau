--!strict
-- Matches: against the bot, casual and ranked PvP (server queue), King of the table.
-- Turns, turn timer, ball in hand, called pocket for the 8, end of the match. The server simulates
-- every shot and applies PoolRules; clients only send intents. Leaving after the first shot loses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local BotPlanner = require(Shared.Pool.BotPlanner)
local Chaos = require(Shared.Config.Chaos)
local ChaosEffects = require(Shared.Pool.Chaos)
local TableGeometry = require(Shared.Pool.TableGeometry)
local TrickConfig = require(Shared.Config.Tricks)
local Tricks = require(Shared.Pool.Tricks)
local Hype = require(Shared.Config.Hype)
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local PoolRules = require(Shared.Pool.PoolRules)
local Rack = require(Shared.Pool.Rack)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Cues = require(Shared.Config.Cues)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Game.Progression)
local Rules = require(Shared.Config.Rules)
local Signal = require(Shared.Util.Signal)
local Social = require(Shared.Config.Social)
local Tables = require(Shared.Config.Tables)
local ShotClassifier = require(Shared.Pool.ShotClassifier)
local ShotReport = require(Shared.Pool.ShotReport)
local Titles = require(Shared.Config.Titles)
local TitleScenarios = require(Shared.Pool.TitleScenarios)
local TrajectoryCodec = require(Shared.Pool.TrajectoryCodec)
local Tutorial = require(Shared.Config.Tutorial)
local Validate = require(Shared.Util.Validate)
local AnalyticsService = require(script.Parent.AnalyticsService)
local BotService = require(script.Parent.BotService)
local CueService = require(script.Parent.CueService)
local DataService = require(script.Parent.DataService)
local EventService = require(script.Parent.EventService)
local HypeService = require(script.Parent.HypeService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local LiveConfigService = require(script.Parent.LiveConfigService)
local QuestService = require(script.Parent.QuestService)
local ShopService = require(script.Parent.ShopService)
local SocialService = require(script.Parent.SocialService)
local SpeedPoolService = require(script.Parent.SpeedPoolService)
local SpiritService = require(script.Parent.SpiritService)
local TableService = require(script.Parent.TableService)

local PLAYBACK_GRACE = 0.6 -- seconds after a trajectory ends before the next turn starts
local LATE_SHOT_GRACE = 0.5 -- accept a shot this long after the turn timer (network delay)
local SPIN_QUEST_MIN = 0.2 -- a pot "with spin" needs at least this tip offset

type Seat = {
	player: Player?,
	level: string?, -- bot level; nil for a human
	name: string,
	userId: number,
	timeouts: number,
	cue: Cues.Cue, -- stats used this match (base in ranked and the tutorial)
}

export type Mode = "Bot" | "Casual" | "Ranked" | "King" | "Chaos" | "Trick" | "Sandbox" | "Speed"

-- Chaos mode state (golden balls, one-shot bonuses, Tiger meter) by seat index.
type ChaosState = {
	golden: { number },
	meter: { number },
	armed: { boolean },
	selfBonus: { [number]: string },
	againstBonus: { [number]: string },
	note: string?, -- last bonus handed out (localization key), shown as a toast
}

type Match = {
	entry: TableService.Entry,
	mode: Mode,
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
	-- The current visit (consecutive shots of one player):
	visitOwnPots: number,
	turnStreak: number,
	combo: number, -- titles in a row
	tutorial: boolean, -- the first break is rigged to give TIGER
	chaos: ChaosState?,
	trick: TrickConfig.Trick?,
}

local matches: { [string]: Match } = {}
-- Players waiting for a human opponent, seated at their own table.
local queued: { [Player]: { mode: Mode, entry: TableService.Entry, since: number } } = {}
local lastMatchCoins: { [Player]: number } = {} -- for the "x2 match reward" rewarded ad
local random = Random.new()
local function roll(): number
	return random:NextNumber()
end
local FREE_MODES = { Sandbox = true, Trick = true } -- no rules, no timer, no rewards
local shotLimiter = RateLimiter.new(1, 2)
local startLimiter = RateLimiter.new(0.5, 2)

local function snapshot(entry: TableService.Entry): Remotes.MatchSnapshot
	local speed = SpeedPoolService.snapshot(entry)
	if speed then
		return speed
	end
	local match = matches[entry.id]
	if not match then
		local host = entry.occupants[1]
		return {
			tableId = entry.id,
			phase = if host and queued[host] then "Queue" else "Idle",
			mode = if host and queued[host] then queued[host].mode else nil,
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
			aim = seat.cue.aim,
		})
	end
	return {
		tableId = entry.id,
		phase = match.phase,
		mode = match.mode,
		players = players,
		current = match.rules.current,
		isBreak = match.rules.isBreak,
		ballInHand = match.ballInHand,
		kitchenOnly = match.kitchenOnly,
		mustCall = PoolRules.mustCallPocket(match.rules, entry.balls, match.rules.current),
		turnEndsAt = match.turnEndsAt,
		reasonKey = match.reasonKey,
		winner = match.winner,
		chaos = if match.chaos
			then {
				golden = match.chaos.golden,
				meter = match.chaos.meter,
				armed = match.chaos.armed,
				fog = match.chaos.againstBonus[match.rules.current] == "Fog",
				note = match.chaos.note,
			}
			else nil,
		trick = if match.trick
			then { id = match.trick.id, nameKey = match.trick.nameKey, target = match.trick.target }
			else nil,
	}
end

local function broadcast(entry: TableService.Entry)
	Remotes.Event("MatchState"):FireAllClients(snapshot(entry))
end

local function turnSeconds(seat: Seat): number
	local base = math.max(Rules.MinTurnSeconds, Rules.TurnSeconds - seat.timeouts * Rules.TimeoutPenaltySeconds)
	return base + seat.cue.time
end

local function findBall(balls: { PoolPhysics.BallState }, id: number): PoolPhysics.BallState?
	for _, b in balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local MatchService = {
	Finished = Signal.new(), -- (entry, mode, winner: Player?, loser: Player?)
}

-- Sandbox: move any ball, re-rack or clear the table. { action = "place", id, x, y } | "rerack" | "clear"
local sandboxLimiter = RateLimiter.new(8, 16)
local function onSandbox(player: Player, payload: unknown)
	local entry, index = TableService.tableOf(player)
	local match = if entry then matches[entry.id] else nil
	if
		not sandboxLimiter:Allow(player)
		or not entry
		or not match
		or match.mode ~= "Sandbox"
		or index ~= 1
		or match.busy
	then
		return
	end
	if type(payload) ~= "table" then
		return
	end
	local raw = payload :: { [unknown]: unknown }
	local balls = table.clone(entry.balls)
	if raw.action == "rerack" then
		TableService.rack(entry)
		return
	elseif raw.action == "clear" then
		for i, b in balls do
			if b.id ~= 0 then
				balls[i] = { id = b.id, x = b.x, y = b.y, status = "Pocketed" }
			end
		end
	elseif raw.action == "place" then
		local id, point = Validate.finite(raw.id), Validate.point(raw)
		if not id or not point then
			return
		end
		local R = entry.geometry.ballRadius
		if math.abs(point.x) > entry.geometry.halfLength - R or math.abs(point.y) > entry.geometry.halfWidth - R then
			return
		end
		for i, b in balls do
			if b.id ~= id and b.status == "Stationary" and (b.x - point.x) ^ 2 + (b.y - point.y) ^ 2 < (2 * R) ^ 2 then
				return
			end
			if b.id == id then
				balls[i] = {
					id = b.id,
					x = point.x,
					y = point.y,
					status = "Stationary",
					qx = b.qx,
					qy = b.qy,
					qz = b.qz,
					qw = b.qw,
				}
			end
		end
	else
		return
	end
	TableService.setBalls(entry, balls, true)
end

local playShot: (Match, PoolPhysics.ShotParams, number?, { x: number, y: number }?, boolean?) -> ()
local startTurn: (Match) -> ()
local refreshTrick: (Progression.PlayerData) -> ()

-- Pays and records the match for every human seat. A player who left gets the loss only.
local function award(match: Match, winner: number, leaver: number?)
	if FREE_MODES[match.mode] then
		return
	end
	for index, seat in match.seats do
		local player = seat.player
		local data = if player then DataService.get(player) else nil
		if not player or not data then
			continue
		end
		local won = index == winner
		if won then
			data.stats.wins += 1
			data.trophies += 1
			QuestService.event(player, "wins")
			LeaderboardService.submit("Wins", player, data.stats.wins)
		else
			data.stats.losses += 1
		end
		QuestService.event(player, "matches")
		if index ~= leaver then
			local coins, xp
			if match.mode == "Bot" then
				coins, xp = Progression.matchReward(match.seats[3 - index].level or "Medium", won)
			else
				local rewards = if match.mode == "Ranked" then Social.RankedRewards else Social.PvpRewards
				coins = if won then rewards.win else rewards.loss
				xp = if won then Economy.Xp.Win else Economy.Xp.Loss
			end
			coins = math.floor(
				coins
					* SocialService.rewardMultiplier(player)
					* ShopService.coinMultiplier(player)
					* EventService.coinMultiplier()
			)
			lastMatchCoins[player] = coins
			DataService.addCurrency(player, "coins", coins, "Gameplay", if won then "MatchWin" else "MatchPlayed")
			DataService.notify(player, "NOTIFY_COINS", { amount = coins })
			DataService.addXp(player, xp * EventService.xpMultiplier())
			AnalyticsService.funnel(player, AnalyticsService.Funnel.MatchFinished, "MatchFinished")
		end
		DataService.changed(player)
	end
	-- Ranked: Elo between the two humans (a leaver loses rating too).
	local a, b = match.seats[1].player, match.seats[2].player
	local dataA = if a then DataService.get(a) else nil
	local dataB = if b then DataService.get(b) else nil
	if match.mode == "Ranked" and a and b and dataA and dataB then
		dataA.rating, dataB.rating =
			Progression.elo(dataA.rating, dataB.rating, if winner == 1 then 1 else 0, Social.RatingK)
		LeaderboardService.submit("Rating", a, dataA.rating)
		LeaderboardService.submit("Rating", b, dataB.rating)
		DataService.changed(a)
		DataService.changed(b)
	end
end

local function finish(match: Match, winner: number, reasonKey: string, leaver: number?)
	match.phase = "Over"
	match.winner = winner
	match.reasonKey = reasonKey
	match.turn += 1
	award(match, winner, leaver)
	broadcast(match.entry)
	MatchService.Finished:Fire(match.entry, match.mode, match.seats[winner].player, match.seats[3 - winner].player)
end

-- Stats, XP, spirits, quests and the shot-of-the-day board for one shot of a human.
local function progressShot(
	player: Player,
	shot: PoolPhysics.ShotParams,
	report: ShotReport.Report,
	title: Titles.Title?,
	ranked: boolean
)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.stats.shots += 1
	data.stats.pots += report.pottedOwn
	local xp = Economy.Xp.Pot * report.pottedOwn
	if report.pottedOwn > 0 then
		QuestService.event(player, "pots", nil, report.pottedOwn)
		if math.max(math.abs(shot.spinX), math.abs(shot.spinY)) >= SPIN_QUEST_MIN then
			QuestService.event(player, "spinPots", nil, report.pottedOwn)
		end
	end
	if title then
		if ranked then
			data.stats.rankedTitles[title.id] = (data.stats.rankedTitles[title.id] or 0) + 1
		end
		for _ = 1, EventService.spiritMultiplier() do
			SpiritService.onTitle(player, title.id)
		end
		QuestService.event(player, "title", title.id)
		if title.kind == "Title" then
			xp += Economy.Xp.Title
			LeaderboardService.submit("ShotOfDay", player, title.priority, true)
		end
	end
	DataService.addXp(player, xp * EventService.xpMultiplier())
	DataService.changed(player)
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
	local seconds = if FREE_MODES[match.mode] then 3600 else turnSeconds(seat)
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
			powerScale = seat.cue.power,
			spinScale = seat.cue.spin,
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
	elseif not FREE_MODES[match.mode] then
		task.delay(seconds, onTimeout, match, turn)
	end
end

-- Chaos: bonuses that change this shot (consumed now).
local function chaosBefore(
	match: Match,
	balls: { PoolPhysics.BallState },
	superShot: boolean
): (TableGeometry.Geometry, PoolPhysics.Params?, { PoolPhysics.BallState }, boolean)
	local entry, chaos = match.entry, match.chaos :: ChaosState
	local current = match.rules.current
	local own, against = chaos.selfBonus[current], chaos.againstBonus[current]
	chaos.selfBonus[current], chaos.againstBonus[current] = nil, nil
	local useSuper = superShot and chaos.armed[current]
	if useSuper then
		chaos.armed[current], chaos.meter[current] = false, 0
	end
	local geometry = entry.geometry
	if against == "NarrowPockets" and entry.variant == "Standard" then
		geometry = TableGeometry.get("Chinese8")
	end
	if own == "Earthquake" then
		balls = ChaosEffects.earthquake(geometry, balls, roll)
	end
	local params = if own == "MoonJump" or useSuper then ChaosEffects.params(own == "MoonJump", useSuper) else nil
	return geometry, params, balls, useSuper
end

-- Chaos after the shot: golden balls hand out bonuses, titles fill the Tiger meter.
local function chaosAfter(
	match: Match,
	sim: PoolPhysics.SimResult,
	outcome: PoolRules.RulesResult,
	title: Titles.Title?
)
	local chaos = match.chaos :: ChaosState
	local current = match.rules.current
	chaos.note = nil
	if not outcome.foul then
		for _, e in sim.events do
			if e.kind == PoolPhysics.EventKind.Pocketed and table.find(chaos.golden, e.a) then
				table.remove(chaos.golden, table.find(chaos.golden, e.a) :: number)
				local bonus = ChaosEffects.pickBonus(roll)
				if bonus.target == "Self" then
					chaos.selfBonus[current] = bonus.id
				else
					chaos.againstBonus[3 - current] = bonus.id
				end
				chaos.note = bonus.nameKey
			end
		end
	end
	if title and title.kind == "Title" and not chaos.armed[current] then
		chaos.meter[current] = math.min(1, chaos.meter[current] + Chaos.MeterPerTitle)
		chaos.armed[current] = chaos.meter[current] >= 1
	end
end

-- Trick of the week: count the attempt, reward the first solve of the week.
local function trickAfter(match: Match, sim: PoolPhysics.SimResult)
	local trick = match.trick :: TrickConfig.Trick
	local player = match.seats[1].player
	local data = if player then DataService.get(player) else nil
	if not player or not data then
		return
	end
	local state = data.trick
	state.attempts += 1
	if Tricks.solved(trick, sim) then
		match.reasonKey = "TRICK_SOLVED"
		if not state.solved then
			state.solved = true
			DataService.addCurrency(player, "coins", TrickConfig.FirstSolveCoins, "Gameplay", `Trick_{trick.id}`)
			DataService.notify(player, "NOTIFY_COINS", { amount = TrickConfig.FirstSolveCoins })
			LeaderboardService.submit("Trick", player, state.totalAttempts + state.attempts)
		end
	else
		match.reasonKey = "TRICK_MISS"
	end
	DataService.changed(player)
end

function playShot(
	match: Match,
	shot: PoolPhysics.ShotParams,
	calledPocket: number?,
	cueBallPos: { x: number, y: number }?,
	superShot: boolean?
)
	local entry = match.entry
	local shooterSeat = match.seats[match.rules.current]
	local shooter = shooterSeat.player
	local cue = shooterSeat.cue
	shot = {
		angle = shot.angle,
		power = shot.power * cue.power,
		spinX = shot.spinX * cue.spin,
		spinY = shot.spinY * cue.spin,
		elevation = shot.elevation,
	}
	if match.tutorial and match.rules.isBreak and shooter and shot.power >= Tutorial.MinPower then
		-- Rigged first break: whatever the newcomer does, it is a TIGER.
		shot = table.clone(Tutorial.BreakShot)
		cueBallPos = { x = Tutorial.CueX, y = Tutorial.CueY }
		match.tutorial = false
	end
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
	local geometry, params, useSuper = entry.geometry, nil, false
	if match.chaos then
		geometry, params, balls, useSuper = chaosBefore(match, balls, superShot == true)
	end
	local sim = PoolPhysics.simulateShot({ geometry = geometry, balls = balls }, shot, { params = params })
	local before = match.rules
	local glitched = false
	if match.chaos and roll() < Chaos.GlitchChance then
		glitched = ChaosEffects.glitch(sim, before.groups[before.current], roll) ~= nil
	end
	local outcome: PoolRules.RulesResult
	if FREE_MODES[match.mode] then
		outcome = {
			foul = nil,
			nextPlayer = before.current,
			ballInHand = false,
			groups = before.groups,
			gameOver = false,
			winner = nil,
			respotEight = false,
			reasonKey = "",
		}
	else
		outcome = PoolRules.evaluate(before, match.variant, sim, { calledPocket = calledPocket })
	end
	local report = ShotReport.build({
		glitched = glitched,
		allOwn = match.mode == "Sandbox",
		sim = sim,
		shot = shot,
		before = before,
		outcome = outcome,
		ballsBefore = balls,
		geometry = entry.geometry,
		visitOwnPots = match.visitOwnPots,
		turnStreak = match.turnStreak + 1,
	})
	local title = ShotClassifier.classify(report, LiveConfigService.get().disabledTitles)
	if useSuper or (EventService.allTiger() and report.pottedOwn > 0) then
		title = ShotClassifier.byId("TIGER") -- the Tiger super shot always gets its splash
	end
	if match.chaos then
		chaosAfter(match, sim, outcome, title)
	end
	HypeService.recordShot(if title then title.id else nil)
	local hype: Remotes.HypePayload? = nil
	if title then
		match.combo = if title.kind == "Title" then math.min(match.combo + 1, Hype.MaxCombo) else 0
		hype = {
			titleId = title.id,
			combo = math.max(match.combo, 1),
			rarity = HypeService.rarity(title.id),
			playerName = shooterSeat.name,
		}
		if shooter then
			HypeService.announce(shooter.DisplayName, title)
			if title.id == "TIGER" then
				AnalyticsService.funnel(shooter, AnalyticsService.Funnel.FirstTiger, "FirstTiger")
			end
			AnalyticsService.custom(shooter, `Title_{title.id}`)
		end
	else
		match.combo = 0
	end
	if shooter then
		AnalyticsService.funnel(shooter, AnalyticsService.Funnel.FirstShot, "FirstShot")
		if not FREE_MODES[match.mode] then
			progressShot(shooter, shot, report, title, match.mode == "Ranked")
		end
	end
	if outcome.nextPlayer == before.current and not outcome.gameOver then
		match.visitOwnPots += report.pottedOwn
		match.turnStreak += 1
	else
		match.visitOwnPots, match.turnStreak, match.combo = 0, 0, 0
	end
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
		hype = hype,
	}
	-- ponytail: every client gets every table's shots; limit to nearby players when tables multiply (phase 7).
	Remotes.Event("ShotResult"):FireAllClients(message)

	match.rules = { current = outcome.nextPlayer, groups = outcome.groups, isBreak = false }
	match.ballInHand = outcome.ballInHand
	match.kitchenOnly = false
	match.reasonKey = if FREE_MODES[match.mode] then nil else outcome.reasonKey
	if match.trick then
		trickAfter(match, sim)
	end
	local turn = match.turn
	local splash = if hype then math.min(Hype.SplashSeconds, Hype.MaxSplashWait) else 0
	task.delay(sim.duration + PLAYBACK_GRACE + splash, function()
		if matches[entry.id] ~= match or match.turn ~= turn then
			return
		end
		match.busy = false
		local trick = match.trick
		if trick then
			-- Every attempt starts from the trick layout; out of tries ends the session.
			local player = match.seats[1].player
			local data = if player then DataService.get(player) else nil
			if not data or data.trick.attempts >= data.trick.limit then
				finish(match, 2, "TRICK_OUT_OF_TRIES")
				return
			end
			TableService.setBalls(entry, Tricks.layout(trick), true)
		end
		if outcome.gameOver then
			finish(match, outcome.winner :: number, outcome.reasonKey)
		else
			startTurn(match)
		end
	end)
end

local function onShot(player: Player, payload: unknown)
	if SpeedPoolService.shoot(player, payload) then
		return
	end
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
	playShot(match, shot, calledPocket, cueBallPos, raw.superShot == true)
end

local function humanSeat(player: Player, baseCue: boolean): Seat
	return {
		player = player,
		level = nil,
		name = player.DisplayName,
		userId = player.UserId,
		timeouts = 0,
		cue = CueService.stats(player, baseCue),
	}
end

local function botSeat(level: string): Seat
	return {
		player = nil,
		level = level,
		name = `BOT_{string.upper(level)}`,
		userId = 0,
		timeouts = 0,
		cue = CueService.stats(nil, true),
	}
end

local function startMatch(entry: TableService.Entry, seats: { Seat }, mode: Mode, tutorial: boolean)
	local existing = matches[entry.id]
	if existing and existing.phase == "Playing" then
		return
	end
	local trick = if mode == "Trick" then Tricks.forTime(os.time()) else nil
	if trick then
		TableService.setBalls(entry, Tricks.layout(trick), true)
	elseif tutorial then
		TableService.setBalls(entry, Rack.eightBall(entry.geometry, Tutorial.RackSeed), true)
	else
		TableService.rack(entry)
	end
	local variant = Rules.Variants[entry.variant]
	local breaker = if mode == "Bot" or mode == "Chaos" or FREE_MODES[mode] then 1 else math.random(1, 2)
	local free = FREE_MODES[mode] == true
	local match: Match = {
		entry = entry,
		mode = mode,
		seats = seats,
		rules = { current = breaker, groups = {}, isBreak = not free },
		variant = variant,
		phase = "Playing",
		ballInHand = not free,
		kitchenOnly = variant.BreakFromKitchen and not free,
		turn = 0,
		turnEndsAt = 0,
		busy = false,
		started = false,
		reasonKey = nil,
		winner = nil,
		visitOwnPots = 0,
		turnStreak = 0,
		combo = 0,
		tutorial = tutorial,
		chaos = if mode == "Chaos"
			then {
				golden = ChaosEffects.pickGolden(entry.balls, Chaos.GoldenBalls, roll),
				meter = { 0, 0 },
				armed = { false, false },
				selfBonus = {},
				againstBonus = {},
				note = nil,
			}
			else nil,
		trick = trick,
	}
	matches[entry.id] = match
	startTurn(match)
end

-- Two humans at `entry` (both already seated there).
function MatchService.startPvp(entry: TableService.Entry, a: Player, b: Player, mode: Mode)
	local base = mode == "Ranked"
	startMatch(entry, { humanSeat(a, base), humanSeat(b, base) }, mode, false)
end

-- The player can claim "x2 match reward" for their last finished match.
function MatchService.lastMatchCoins(player: Player): number
	return lastMatchCoins[player] or 0
end

-- True while it is this player's turn in a running match (ads never play then).
function MatchService.isPlayersTurn(player: Player): boolean
	local entry = TableService.tableOf(player)
	local match = if entry then matches[entry.id] else nil
	return match ~= nil and match.phase == "Playing" and match.seats[match.rules.current].player == player
end

function MatchService.isPlaying(entry: TableService.Entry): boolean
	local match = matches[entry.id]
	return match ~= nil and match.phase == "Playing"
end

-- Trick of the week attempts reset every UTC day; the week's solve state resets every week.
function refreshTrick(data: Progression.PlayerData)
	local state = data.trick
	local now = os.time()
	local week, day = Progression.weekIndex(now), Progression.dayIndex(now)
	if state.week ~= week then
		state.week, state.solved, state.totalAttempts = week, false, 0
	end
	if state.day ~= day then
		state.totalAttempts += state.attempts
		state.day, state.attempts, state.limit = day, 0, TrickConfig.DailyAttempts
	end
end

local function leaveQueue(player: Player)
	local entry = queued[player]
	if entry then
		queued[player] = nil
		broadcast(entry.entry)
	end
end

-- Queues a seated player for a human opponent; pairs with someone already waiting in the same mode.
local function enqueue(player: Player, entry: TableService.Entry, mode: Mode)
	for other, waiting in queued do
		if other ~= player and waiting.mode == mode then
			queued[other] = nil
			local host = waiting.entry
			if TableService.seatAt(player, host, 2) then
				if mode == "Speed" then
					SpeedPoolService.start(host, other, player)
				else
					MatchService.startPvp(host, other, player, mode)
				end
				return
			end
		end
	end
	local since = os.clock()
	queued[player] = { mode = mode, entry = entry, since = since }
	broadcast(entry)
	task.delay(Social.QueueSeconds, function()
		local waiting = queued[player]
		if waiting and waiting.since == since then
			leaveQueue(player)
			DataService.notify(player, "PVP_NO_OPPONENT")
		end
	end)
end

-- payload: a bot level ("Easy" | "Medium" | "Hard") or "Casual" / "Ranked" for a human opponent.
local function onStart(player: Player, payload: unknown)
	local entry, index = TableService.tableOf(player)
	if not startLimiter:Allow(player) or not entry or index ~= 1 or entry.id == Tables.KingTableId then
		return
	end
	leaveQueue(player)
	if payload == "Cancel" or (type(payload) == "string" and not LiveConfigService.enabled(payload)) then
		return
	end
	if SpeedPoolService.isPlaying(entry) then
		return
	end
	if entry.occupants[2] and not MatchService.isPlaying(entry) then
		TableService.unseat(entry.occupants[2]) -- the previous opponent's seat is freed for a new match
	end
	local level = Validate.botLevel(payload)
	if level then
		startMatch(entry, { humanSeat(player, false), botSeat(level) }, "Bot", false)
	elseif payload == "Casual" or payload == "Ranked" or payload == "Speed" then
		enqueue(player, entry, payload)
	elseif payload == "Chaos" then
		startMatch(entry, { humanSeat(player, false), botSeat(Chaos.BotLevel) }, "Chaos", false)
	elseif payload == "Sandbox" then
		startMatch(entry, { humanSeat(player, false), botSeat("Easy") }, "Sandbox", false)
	elseif payload == "Trick" then
		local data = DataService.get(player)
		if data and entry.variant == "Standard" then
			refreshTrick(data)
			if data.trick.attempts < data.trick.limit then
				startMatch(entry, { humanSeat(player, true), botSeat("Easy") }, "Trick", false)
			else
				DataService.notify(player, "TRICK_OUT_OF_TRIES")
			end
		end
	end
end

local function onTutorial(player: Player)
	if not startLimiter:Allow(player) then
		return
	end
	local entry = TableService.tableOf(player) or TableService.get(Tutorial.TableId)
	if entry and TableService.seatAt(player, entry, 1) then
		startMatch(entry, { humanSeat(player, true), botSeat(Tutorial.BotLevel) }, "Bot", true)
	end
end

-- Studio only: lay out the scenario of a title on the player's table and play its known shot.
local function onDebug(player: Player, payload: unknown)
	if not RunService:IsStudio() or type(payload) ~= "table" then
		return
	end
	local raw = payload :: { [unknown]: unknown }
	local entry = TableService.tableOf(player)
	local match = if entry then matches[entry.id] else nil
	local scenario = if type(raw.id) == "string" then TitleScenarios.all()[raw.id] else nil
	if not entry or not match or not scenario or not scenario.shot or match.busy or entry.variant ~= "Standard" then
		return
	end
	TableService.setBalls(entry, scenario.balls, true)
	match.rules = { current = 1, groups = scenario.rules.groups, isBreak = scenario.rules.isBreak }
	match.visitOwnPots = scenario.visitOwnPots
	match.phase = "Playing"
	match.turn += 1
	task.delay(1, playShot, match, scenario.shot, scenario.calledPocket, nil)
end

local function onUnseated(player: Player, entry: TableService.Entry)
	queued[player] = nil
	local match = matches[entry.id]
	local inMatch = false
	if match then
		for _, seat in match.seats do
			inMatch = inMatch or seat.player == player
		end
	end
	if match and inMatch then
		match.turn += 1 -- invalidates timers and a thinking bot
		if match.phase == "Playing" and match.started then
			local leaver = if match.seats[1].player == player then 1 else 2
			finish(match, 3 - leaver, "RULE_LOSS_LEFT", leaver)
		elseif match.phase == "Playing" then
			MatchService.Finished:Fire(entry, match.mode, nil, nil) -- cancelled before the first shot
		end
		matches[entry.id] = nil
	end
	broadcast(entry)
end

function MatchService.Start()
	Remotes.Event("Shot").OnServerEvent:Connect(onShot)
	Remotes.Event("StartMatch").OnServerEvent:Connect(onStart)
	Remotes.Event("StartTutorial").OnServerEvent:Connect(onTutorial)
	Remotes.Event("Debug").OnServerEvent:Connect(onDebug)
	TableService.Seated:Connect(function(player, entry)
		AnalyticsService.funnel(player, AnalyticsService.Funnel.SatAtTable, "SatAtTable")
		broadcast(entry)
	end)
	TableService.Unseated:Connect(onUnseated)
	ShopService.onAdReward("TrickRetry", function(player)
		local data = DataService.get(player)
		if data then
			refreshTrick(data)
			data.trick.limit += 1
			DataService.changed(player)
		end
	end)
	Remotes.Event("Sandbox").OnServerEvent:Connect(onSandbox)
	ShopService.onAdReward("MatchX2", function(player)
		local coins = lastMatchCoins[player]
		if coins and coins > 0 then
			lastMatchCoins[player] = nil
			DataService.addCurrency(player, "coins", coins, "ContextualPurchase", "AdMatchX2")
			DataService.notify(player, "NOTIFY_COINS", { amount = coins })
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastMatchCoins[player] = nil
		shotLimiter:Forget(player)
		startLimiter:Forget(player)
	end)
end

return MatchService
