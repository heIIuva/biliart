--!strict
-- Event banner (GDD 16-17): the running mini event or a countdown to the next one, the holiday,
-- the weekly event and the live-config news line. Live title renames go into Text overrides.
-- Admins (Config.Admins, checked again on the server) get a small panel with event effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Admins = require(Shared.Config.Admins)
local Remotes = require(Shared.Net.Remotes)
local Text = require(Shared.Util.Text)
local Titles = require(Shared.Config.Titles)
local Kit = require(script.Parent.Parent.UI.Kit)
local MenuController = require(script.Parent.MenuController)
local TableViewController = require(script.Parent.TableViewController)

local ADMIN_EFFECTS = { "AllTiger", "GoldenRain", "TripleRewards" }
local ADMIN_MINUTES = 30

local state: { [string]: any }? = nil
local news: { en: string, ru: string }? = nil
local banner: TextLabel
local newsLabel: TextLabel

local EventController = {}

local function clock(seconds: number): string
	seconds = math.max(0, seconds)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function update()
	if not state then
		return
	end
	local now = workspace:GetServerTimeNow()
	local lines = {}
	local mini = state.mini
	if mini then
		table.insert(
			lines,
			Text.format(
				"EVENT_RUNNING",
				{ name = Text.get("EVENT_" .. string.upper(mini.id)), time = clock(mini.endsAt - now) }
			)
		)
	else
		table.insert(
			lines,
			Text.format(
				"EVENT_NEXT",
				{ name = Text.get("EVENT_" .. string.upper(state.nextMini.id)), time = clock(state.nextMini.at - now) }
			)
		)
	end
	if state.holiday then
		table.insert(lines, Text.format("EVENT_HOLIDAY", { name = Text.get(state.holiday) }))
	end
	if state.weekly.active then
		table.insert(lines, Text.get("EVENT_WEEKLY"))
	end
	for effect in state.admin do
		table.insert(lines, Text.get("ADMIN_" .. string.upper(effect)))
	end
	banner.Text = table.concat(lines, "  ·  ")
end

local function buildAdmin(gui: ScreenGui)
	local panel = Kit.frame("Admin", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(300, 250),
		Visible = false,
		Active = true,
	})
	Kit.corner(panel, 0.06)
	for i, effect in ADMIN_EFFECTS do
		Kit.button(effect, panel, "ADMIN_" .. string.upper(effect), {
			Position = UDim2.fromOffset(20, 14 + (i - 1) * 54),
			Size = UDim2.fromOffset(260, 46),
		}, function()
			Remotes.Event("AdminCommand"):FireServer({ effect = effect, minutes = ADMIN_MINUTES })
		end)
	end
	Kit.button("Close", panel, "MENU_CLOSE", {
		Position = UDim2.fromOffset(80, 190),
		Size = UDim2.fromOffset(140, 44),
		BackgroundColor3 = Kit.GREY,
	}, function()
		panel.Visible = false
	end)
	MenuController.addButton("MENU_ADMIN", 22, function()
		panel.Visible = true
	end, panel)
end

function EventController.Start()
	local gui = Kit.screen("Events", 6) -- the admin panel opens above the menu
	banner = Kit.label("Banner", gui, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56), -- below the currency bar
		Size = UDim2.fromOffset(520, 28),
		TextSize = 16,
		TextColor3 = Kit.GOLD,
		TextStrokeTransparency = 0.4,
	})
	newsLabel = Kit.label("News", gui, "", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(520, 24),
		TextSize = 14,
		TextStrokeTransparency = 0.4,
	})
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	TableViewController.SeatChanged:Connect(function(tableId)
		gui.Enabled = tableId == nil -- the match HUD uses the top of the screen
	end)
	if table.find(Admins.UserIds, Players.LocalPlayer.UserId) then
		buildAdmin(gui)
	end
	Remotes.Event("EventState").OnClientEvent:Connect(function(s)
		state = s
		update()
	end)
	Remotes.Event("LiveConfig").OnClientEvent:Connect(function(config)
		for _, title in Titles do
			Text.override(title.nameKey, config.titleNames[title.id])
		end
		news = config.news
		Text.override("LIVE_NEWS", news)
		newsLabel.Text = if news then Text.get("LIVE_NEWS") else ""
	end)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed >= 1 then
			elapsed = 0
			update()
		end
	end)
end

return EventController
