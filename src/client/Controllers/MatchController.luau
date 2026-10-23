--!strict
-- Match state on this client: shows the level picker, whose turn it is, the turn timer, the
-- outcome of the last shot and the result; tells AimController when the local player may shoot.
-- A new turn is shown only after the previous shot has finished playing back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Text = require(Shared.Util.Text)
local MatchHud = require(script.Parent.Parent.UI.MatchHud)
local TableViewController = require(script.Parent.TableViewController)

local GROUP_KEYS = { Solids = "GROUP_SOLIDS", Stripes = "GROUP_STRIPES" }

local player = Players.LocalPlayer
local snapshots: { [string]: Remotes.MatchSnapshot } = {}
local shown: Remotes.MatchSnapshot? = nil -- what the HUD displays for the seated table
local lastLevel = "Medium"
local turnTotal = 1 -- seconds the current turn had when it was shown
local hud: MatchHud.Hud

local MatchController = {}

local function myIndex(snapshot: Remotes.MatchSnapshot): number?
	for i, p in snapshot.players do
		if not p.isBot and p.userId == player.UserId then
			return i
		end
	end
	return nil
end

-- The match the local player sees right now (seated table, playback finished).
function MatchController.current(): Remotes.MatchSnapshot?
	return shown
end

function MatchController.canShoot(): boolean
	local snapshot = shown
	return snapshot ~= nil
		and snapshot.phase == "Playing"
		and myIndex(snapshot) == snapshot.current
		and Workspace:GetServerTimeNow() < snapshot.turnEndsAt
end

function MatchController.flash(key: string)
	hud.toast(key)
end

local function playerLine(snapshot: Remotes.MatchSnapshot, index: number): MatchHud.PlayerLine?
	local p = snapshot.players[index]
	if not p then
		return nil
	end
	local group = p.group
	return {
		name = if p.isBot then Text.get(p.name) else p.name,
		groupKey = if group then GROUP_KEYS[group] else (if snapshot.isBreak then nil else "GROUP_OPEN"),
		active = snapshot.phase == "Playing" and snapshot.current == index,
	}
end

local function render()
	local view = TableViewController.seatedView()
	if not view then
		shown = nil
		hud.setVisible(false)
		return
	end
	if view.playback then
		return -- wait for StateChanged
	end
	local snapshot = snapshots[view.id]
	local previous = shown
	shown = snapshot
	hud.setVisible(true)
	local phase = if snapshot then snapshot.phase else "Idle"
	hud.showPicker(phase == "Idle")
	if not snapshot or phase == "Idle" then
		hud.showStatus(nil, nil)
		hud.setHint(nil)
		hud.showResult(nil, nil)
		return
	end
	local me = myIndex(snapshot) or 1
	hud.showStatus(playerLine(snapshot, me), playerLine(snapshot, 3 - me))

	if phase == "Over" then
		hud.setHint(nil)
		hud.showResult(if snapshot.winner == me then "MATCH_YOU_WIN" else "MATCH_YOU_LOSE", snapshot.reasonKey)
		return
	end
	hud.showResult(nil, nil)

	local mine = snapshot.current == me
	local hint
	if not mine then
		local opponent = snapshot.players[snapshot.current]
		hint = if opponent and opponent.isBot then "MATCH_BOT_THINKING" else "MATCH_OPPONENT_TURN"
	elseif snapshot.isBreak then
		hint = "HINT_BREAK"
	elseif snapshot.mustCall then
		hint = "HINT_CALL_POCKET"
	elseif snapshot.ballInHand then
		hint = "HINT_BALL_IN_HAND"
	else
		hint = "MATCH_YOUR_TURN"
	end
	hud.setHint(hint)

	-- A new turn: announce what the last shot did.
	local newTurn = not previous or previous.turnEndsAt ~= snapshot.turnEndsAt
	if newTurn then
		turnTotal = math.max(1, snapshot.turnEndsAt - Workspace:GetServerTimeNow())
		if snapshot.reasonKey then
			hud.toast(snapshot.reasonKey)
		end
	end
end

function MatchController.Init()
	hud = MatchHud.new({
		onStart = function(level)
			lastLevel = level
			Remotes.Event("StartMatch"):FireServer(level)
		end,
		onAgain = function()
			Remotes.Event("StartMatch"):FireServer(lastLevel)
		end,
		onLeave = function()
			Remotes.Event("LeaveTable"):FireServer()
		end,
	})
end

function MatchController.Start()
	Remotes.Event("MatchState").OnClientEvent:Connect(function(snapshot: Remotes.MatchSnapshot)
		snapshots[snapshot.tableId] = snapshot
		render()
	end)
	TableViewController.SeatChanged:Connect(function()
		shown = nil
		render()
	end)
	TableViewController.StateChanged:Connect(render)
	RunService.Heartbeat:Connect(function()
		local snapshot = shown
		if snapshot and snapshot.phase == "Playing" then
			local left = snapshot.turnEndsAt - Workspace:GetServerTimeNow()
			hud.setTimer(left / turnTotal)
		end
	end)
end

return MatchController
