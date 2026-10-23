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
local Speed = require(Shared.Config.Speed)
local Tables = require(Shared.Config.Tables)
local Text = require(Shared.Util.Text)
local MatchHud = require(script.Parent.Parent.UI.MatchHud)
local AdController = require(script.Parent.AdController)
local SpeedController = require(script.Parent.SpeedController)
local TableViewController = require(script.Parent.TableViewController)

local GROUP_KEYS = { Solids = "GROUP_SOLIDS", Stripes = "GROUP_STRIPES" }

local player = Players.LocalPlayer
local snapshots: { [string]: Remotes.MatchSnapshot } = {}
local shown: Remotes.MatchSnapshot? = nil -- what the HUD displays for the seated table
local lastLevel = "Medium"
local superOn = false
local restoreGui: ScreenGui? = nil
local turnTotal = 1 -- seconds the current turn had when it was shown
local hud: MatchHud.Hud
local setUiHidden: (boolean) -> ()

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
	if snapshot and snapshot.mode == "Speed" then
		return snapshot.phase == "Playing" and SpeedController.myCueResting(snapshot.tableId)
	end
	return snapshot ~= nil
		and snapshot.phase == "Playing"
		and myIndex(snapshot) == snapshot.current
		and Workspace:GetServerTimeNow() < snapshot.turnEndsAt
end

-- Chaos: the next shot is the Tiger super shot (armed and toggled on).
function MatchController.superShot(): boolean
	return superOn
end

function MatchController.shotSent()
	superOn = false
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

-- Sandbox "hide UI": every screen goes away except one small button that brings them back.
local hiddenGuis: { ScreenGui } = {}
function setUiHidden(hidden: boolean)
	local playerGui = player:WaitForChild("PlayerGui")
	if hidden then
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") and gui.Enabled and gui ~= restoreGui then
				gui.Enabled = false
				table.insert(hiddenGuis, gui)
			end
		end
		if not restoreGui then
			local gui = Instance.new("ScreenGui")
			gui.Name = "ShowUi"
			gui.ResetOnSpawn = false
			local b = Instance.new("TextButton")
			b.Size = UDim2.fromOffset(44, 44)
			b.Position = UDim2.new(0, 8, 1, -52)
			b.Text = "👁"
			b.TextScaled = true
			b.BackgroundTransparency = 0.6
			b.Parent = gui
			b.Activated:Connect(function()
				setUiHidden(false)
			end)
			gui.Parent = playerGui
			restoreGui = gui
		end
		(restoreGui :: ScreenGui).Enabled = true
	else
		for _, gui in hiddenGuis do
			gui.Enabled = true
		end
		table.clear(hiddenGuis)
		if restoreGui then
			restoreGui.Enabled = false
		end
	end
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
	local kingTable = view.id == Tables.KingTableId
	hud.showPicker(phase == "Idle" and not kingTable)
	hud.showSearching(phase == "Queue")
	if not snapshot or phase == "Idle" or phase == "Queue" then
		hud.showStatus(nil, nil)
		hud.setHint(nil)
		hud.showResult(nil, nil)
		return
	end
	local me = myIndex(snapshot) or 1
	hud.showStatus(playerLine(snapshot, me), playerLine(snapshot, if snapshot.players[2] then 3 - me else me))
	local chaos = snapshot.chaos
	if chaos then
		superOn = superOn and chaos.armed[me]
		hud.setChaos(chaos.meter[me], chaos.armed[me], superOn)
		TableViewController.setHighlights(view, chaos.golden)
		TableViewController.setFog(view, chaos.fog and snapshot.current == me and phase == "Playing")
	else
		hud.setChaos(nil, false, false)
		TableViewController.setHighlights(view, {})
		TableViewController.setFog(view, false)
	end
	hud.setSandbox(snapshot.mode == "Sandbox" and phase == "Playing")

	if phase == "Over" then
		hud.setHint(nil)
		hud.setSandbox(false)
		local wasShown = previous ~= nil and previous.phase == "Over"
		hud.showResult(if snapshot.winner == me then "MATCH_YOU_WIN" else "MATCH_YOU_LOSE", snapshot.reasonKey)
		if not wasShown then
			local placement = if snapshot.mode == "Trick" then "TrickRetry" else "MatchX2"
			hud.resultAdButton.Text = Text.get(if placement == "TrickRetry" then "AD_TRICK_RETRY" else "AD_MATCH_X2")
			hud.resultAdButton:SetAttribute("Placement", placement)
			AdController.whenAvailable(placement, hud.resultAdButton, function()
				hud.resultAdButton.Visible = true
			end)
		end
		return
	end
	hud.showResult(nil, nil)

	local mine = snapshot.current == me
	local hint: string? = nil
	if snapshot.mode == "Speed" then
		SpeedController.setMyCue(if me == 2 then Speed.SecondCueId else 0)
		local left = math.max(0, math.floor(snapshot.turnEndsAt - Workspace:GetServerTimeNow()))
		hud.setHint(nil)
		hud.setHintText(Text.format("SPEED_HINT", { time = string.format("%d:%02d", left // 60, left % 60) }))
		return
	elseif not mine then
		local opponent = snapshot.players[snapshot.current]
		hint = if opponent and opponent.isBot then "MATCH_BOT_THINKING" else "MATCH_OPPONENT_TURN"
	elseif snapshot.mode == "Sandbox" then
		hint = "SANDBOX_HINT"
	elseif snapshot.trick then
		hint = nil -- the goal text is set below
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
	local trick = snapshot.trick
	if trick and mine then
		hud.setHintText(Text.format("TRICK_GOAL", { name = Text.get(trick.nameKey), target = trick.target }))
	end

	-- A new turn: announce what the last shot did.
	local newTurn = not previous or previous.turnEndsAt ~= snapshot.turnEndsAt
	if newTurn then
		turnTotal = math.max(1, snapshot.turnEndsAt - Workspace:GetServerTimeNow())
		if snapshot.reasonKey then
			hud.toast(snapshot.reasonKey)
		end
		if chaos and chaos.note then
			task.delay(1.2, hud.toast, chaos.note)
		end
	end
end

function MatchController.Init()
	hud = MatchHud.new({
		onStart = function(level)
			if level ~= "Cancel" then
				lastLevel = level
			end
			Remotes.Event("StartMatch"):FireServer(level)
		end,
		onAgain = function()
			Remotes.Event("StartMatch"):FireServer(lastLevel)
		end,
		onLeave = function()
			Remotes.Event("LeaveTable"):FireServer()
		end,
		onAd = function()
			hud.resultAdButton.Visible = false
			local placement = hud.resultAdButton:GetAttribute("Placement")
			AdController.request(if type(placement) == "string" then placement else "MatchX2")
		end,
		onSuper = function()
			superOn = not superOn
			render()
		end,
		onSandbox = function(action)
			if action == "rerack" or action == "clear" then
				Remotes.Event("Sandbox"):FireServer({ action = action })
			elseif action == "camera" then
				TableViewController.toggleFreeCamera()
			elseif action == "hideUi" then
				setUiHidden(true)
			end
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
