--!strict
-- Speed pool (GDD 12): a continuous simulation (PoolPhysics.newWorld) stepped every frame; each
-- player strikes their own cue ball whenever it rests. Live state goes to clients ~20 times a
-- second (unreliable, compact buffer); pots and sounds go as reliable events.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local PoolPhysics = require(Shared.Pool.PoolPhysics)
local Rack = require(Shared.Pool.Rack)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Social = require(Shared.Config.Social)
local Speed = require(Shared.Config.Speed)
local TrajectoryCodec = require(Shared.Pool.TrajectoryCodec)
local Validate = require(Shared.Util.Validate)
local DataService = require(script.Parent.DataService)
local TableService = require(script.Parent.TableService)

local Kind = PoolPhysics.EventKind

type Game = {
	entry: TableService.Entry,
	world: PoolPhysics.World,
	players: { Player },
	cueIds: { number },
	scores: { number },
	toucher: { [number]: number }, -- object ball -> player index whose cue last touched it
	endsAt: number,
	sendAccumulator: number,
	over: boolean,
}

local games: { [string]: Game } = {}
local shotLimiter = RateLimiter.new(2, 3)

local SpeedPoolService = {}

local function indexOf(game: Game, player: Player): number?
	return table.find(game.players, player)
end

local function snapshot(game: Game, winner: number?): Remotes.MatchSnapshot
	local players: { Remotes.MatchPlayer } = {}
	for i, player in game.players do
		table.insert(players, {
			name = `{player.DisplayName} · {game.scores[i]}`,
			userId = player.UserId,
			isBot = false,
			group = nil,
			aim = 1,
		})
	end
	return {
		tableId = game.entry.id,
		phase = if game.over then "Over" else "Playing",
		mode = "Speed",
		players = players,
		current = 0, -- everyone shoots
		isBreak = false,
		ballInHand = false,
		kitchenOnly = false,
		mustCall = false,
		turnEndsAt = game.endsAt,
		reasonKey = if game.over then "SPEED_OVER" else nil,
		winner = winner,
	}
end

local function broadcast(game: Game, winner: number?)
	Remotes.Event("MatchState"):FireAllClients(snapshot(game, winner))
end

local function finish(game: Game)
	if game.over then
		return
	end
	game.over = true
	local winner = if game.scores[1] > game.scores[2] then 1 elseif game.scores[2] > game.scores[1] then 2 else 0
	for i, player in game.players do
		local won = i == winner
		local coins = if won then Social.PvpRewards.win else Social.PvpRewards.loss
		if DataService.get(player) then
			DataService.addCurrency(player, "coins", coins, "Gameplay", "SpeedPool")
			DataService.notify(player, "NOTIFY_COINS", { amount = coins })
		end
	end
	broadcast(game, if winner == 0 then nil else winner)
	games[game.entry.id] = nil
	TableService.rack(game.entry)
end

-- Scoring: follow who touched what; pots score for the last toucher.
local function process(game: Game, events: { PoolPhysics.Event })
	local ownerOf: { [number]: number } = {}
	for i, id in game.cueIds do
		ownerOf[id] = i
	end
	local scored = false
	for _, e in events do
		if e.kind == Kind.BallBall then
			local a, b = e.a, e.b
			local fromA = ownerOf[a] or game.toucher[a]
			local fromB = ownerOf[b] or game.toucher[b]
			if fromA and not ownerOf[b] then
				game.toucher[b] = fromA
			end
			if fromB and not ownerOf[a] then
				game.toucher[a] = fromB
			end
		elseif e.kind == Kind.Pocketed or e.kind == Kind.OffTable then
			local owner = ownerOf[e.a]
			if owner then
				game.scores[owner] = math.max(0, game.scores[owner] - Speed.ScratchPenalty)
				local id = e.a
				task.delay(Speed.RespawnSeconds, function()
					if games[game.entry.id] == game then
						local x = if owner == 1 then game.entry.geometry.headSpotX else -game.entry.geometry.headSpotX
						game.world.place(id, x, if owner == 1 then 0.2 else -0.2)
					end
				end)
			else
				local by = game.toucher[e.a]
				if by and e.kind == Kind.Pocketed then
					game.scores[by] += if e.a == 8 then Speed.EightPoints else 1
				end
			end
			scored = true
		end
	end
	if #events > 0 then
		Remotes.Event("SpeedEvents"):FireAllClients(game.entry.id, events)
	end
	if scored then
		broadcast(game)
	end
end

local function sendState(game: Game)
	local data = {}
	local objects = 0
	for _, b in game.world.balls() do
		if b.status ~= "Pocketed" and b.status ~= "OffTable" then
			local n = #data
			data[n + 1], data[n + 2], data[n + 3], data[n + 4] = b.id, b.x, b.y, b.z
			data[n + 5], data[n + 6], data[n + 7], data[n + 8] = b.qx, b.qy, b.qz, b.qw
			if not table.find(game.cueIds, b.id) then
				objects += 1
			end
		end
	end
	local frame = TrajectoryCodec.encodeFrame(game.world.time(), data)
	Remotes.Unreliable("SpeedState"):FireAllClients(game.entry.id, frame)
	if objects == 0 then
		finish(game)
	end
end

-- Starts a speed game between two players seated at `entry` (seats 1 and 2).
function SpeedPoolService.start(entry: TableService.Entry, a: Player, b: Player)
	local balls = Rack.eightBall(entry.geometry, math.random(1, 2147483646))
	table.insert(balls, { id = Speed.SecondCueId, x = -entry.geometry.headSpotX, y = 0, status = "Stationary" })
	TableService.setBalls(entry, balls, true)
	local game: Game = {
		entry = entry,
		world = PoolPhysics.newWorld({ geometry = entry.geometry, balls = balls }),
		players = { a, b },
		cueIds = { 0, Speed.SecondCueId },
		scores = { 0, 0 },
		toucher = {},
		endsAt = Workspace:GetServerTimeNow() + Speed.MatchSeconds,
		sendAccumulator = 0,
		over = false,
	}
	games[entry.id] = game
	broadcast(game)
end

-- Handles a shot if the player is in a speed game; true if it was theirs to handle.
function SpeedPoolService.shoot(player: Player, payload: unknown): boolean
	local entry = TableService.tableOf(player)
	local game = if entry then games[entry.id] else nil
	if not game then
		return false
	end
	local index = indexOf(game, player)
	local shot = Validate.shotParams(payload)
	if game.over or not index or not shot or not shotLimiter:Allow(player) then
		return true
	end
	game.world.strike(game.cueIds[index], shot)
	return true
end

function SpeedPoolService.snapshot(entry: TableService.Entry): Remotes.MatchSnapshot?
	local game = games[entry.id]
	return if game then snapshot(game, nil) else nil
end

function SpeedPoolService.isPlaying(entry: TableService.Entry): boolean
	return games[entry.id] ~= nil
end

function SpeedPoolService.Start()
	RunService.Heartbeat:Connect(function(dt)
		for _, game in games do
			game.world.advance(dt)
			process(game, game.world.drainEvents())
			game.sendAccumulator += dt
			if game.sendAccumulator >= 1 / Speed.StateHz then
				game.sendAccumulator = 0
				sendState(game)
			end
			if Workspace:GetServerTimeNow() >= game.endsAt then
				finish(game)
			end
		end
	end)
	TableService.Unseated:Connect(function(player, entry)
		local game = games[entry.id]
		local index = if game then indexOf(game, player) else nil
		if game and index then
			game.scores[index] = -1 -- leaving loses
			finish(game)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		shotLimiter:Forget(player)
	end)
end

return SpeedPoolService
