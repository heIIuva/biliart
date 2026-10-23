--!strict
-- Lobby menu (GDD 10): currency/level bar, spirit index, daily reward, quests and cues.
-- Menus are hidden while seated at a table; the currency bar stays.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cues = require(Shared.Config.Cues)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Game.Progression)
local Remotes = require(Shared.Net.Remotes)
local ShotClassifier = require(Shared.Pool.ShotClassifier)
local Spirits = require(Shared.Config.Spirits)
local Text = require(Shared.Util.Text)
local Kit = require(script.Parent.Parent.UI.Kit)
local PlayerDataController = require(script.Parent.PlayerDataController)
local TableViewController = require(script.Parent.TableViewController)

type Page = "Spirits" | "Daily" | "Quests" | "Cues"

local gui: ScreenGui
local coinsLabel: TextLabel
local gemsLabel: TextLabel
local levelLabel: TextLabel
local menuButtons: Frame
local currencyBar: Frame
local panels: { [Page]: { panel: Frame, list: ScrollingFrame } } = {}
local open: Page? = nil
local extraPanels: { GuiObject } = {} -- panels of later phases (dojo, shop, settings): one open at a time

local MenuController = {}

local function grid(list: ScrollingFrame, cell: Vector2)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
end

local function card(list: ScrollingFrame, order: number): Frame
	local f = Kit.frame("Card", list, { LayoutOrder = order, BackgroundColor3 = Color3.fromRGB(45, 30, 24) })
	Kit.corner(f, 0.08)
	return f
end

local function renderSpirits(data: Progression.PlayerData, list: ScrollingFrame)
	grid(list, Vector2.new(180, 200))
	for i, spirit in Spirits.List do
		local state = data.spirits[spirit.id]
		local unlocked = state ~= nil and state.level > 0
		local c = card(list, i)
		Kit.label("Hanzi", c, if unlocked then spirit.hanzi else "?", {
			Size = UDim2.new(1, 0, 0, 70),
			TextSize = 54,
			TextColor3 = if unlocked then Kit.GOLD else Color3.fromRGB(90, 80, 70),
		})
		local hidden = spirit.secret and not unlocked
		Kit.label("Name", c, if hidden then Text.get("SPIRIT_SECRET") else Text.get(spirit.nameKey), {
			Position = UDim2.fromOffset(0, 70),
			Size = UDim2.new(1, 0, 0, 26),
		})
		local info
		if unlocked and state then
			info = Text.format("SPIRIT_LEVEL", { level = state.level, progress = state.progress })
		elseif hidden then
			info = Text.get("SPIRIT_SECRET")
		else
			local names = {}
			for _, titleId in spirit.titles do
				local title = ShotClassifier.byId(titleId)
				if title and not title.secret then
					table.insert(names, Text.get(title.nameKey))
				end
			end
			info = Text.format("SPIRIT_HOW", { titles = table.concat(names, ", ") })
		end
		Kit.label("Info", c, info, {
			Position = UDim2.fromOffset(6, 96),
			Size = UDim2.new(1, -12, 0, 50),
			TextSize = 14,
			TextWrapped = true,
		})
		if unlocked then
			local equipped = data.equippedSpirit == spirit.id
			Kit.button("Equip", c, if equipped then "CUE_EQUIPPED" else "SPIRIT_EQUIP", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.fromOffset(140, 36),
				BackgroundColor3 = if equipped then Kit.GREY else Kit.RED,
			}, function()
				Remotes.Event("EquipSpirit"):FireServer(spirit.id)
			end)
		end
	end
end

local function renderDaily(data: Progression.PlayerData, list: ScrollingFrame)
	grid(list, Vector2.new(100, 150))
	local today = Progression.dayIndex(os.time())
	local nextDay = Progression.claimDaily(data.daily, today)
	for day, reward in Economy.DailyRewards do
		local c = card(list, day)
		if nextDay == day then
			c.BackgroundColor3 = Color3.fromRGB(110, 70, 20)
		end
		Kit.label("Day", c, Text.format("DAILY_DAY", { day = day }), { Size = UDim2.new(1, 0, 0, 30) })
		local text = if reward.gems
			then Text.format("NOTIFY_GEMS", { amount = reward.gems })
			else Text.format("NOTIFY_COINS", { amount = reward.coins or 0 })
		Kit.label("Reward", c, text, {
			Position = UDim2.fromOffset(4, 40),
			Size = UDim2.new(1, -8, 0, 60),
			TextWrapped = true,
			TextColor3 = Kit.GOLD,
		})
	end
	Kit.button("Claim", list, if nextDay then "DAILY_CLAIM" else "DAILY_CLAIMED", {
		LayoutOrder = 100,
		BackgroundColor3 = if nextDay then Kit.RED else Kit.GREY,
	}, function()
		Remotes.Event("ClaimDaily"):FireServer()
	end)
end

local function questRow(list: ScrollingFrame, state: Progression.QuestState, order: number)
	local def = Progression.questDef(state.id)
	if not def then
		return
	end
	local row = card(list, order)
	row.Size = UDim2.new(1, -8, 0, 56)
	Kit.label("Text", row, Text.format(def.textKey, { target = def.target }), {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromScale(0.6, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Kit.label("Progress", row, `{state.progress}/{def.target}`, {
		Position = UDim2.fromScale(0.6, 0),
		Size = UDim2.fromScale(0.15, 1),
		TextColor3 = Kit.GOLD,
	})
	local ready = state.progress >= def.target and not state.claimed
	if ready then
		Kit.button("Claim", row, "QUEST_CLAIM", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(110, 40),
		}, function()
			Remotes.Event("ClaimQuest"):FireServer(state.id)
		end)
	end
end

local function renderQuests(data: Progression.PlayerData, list: ScrollingFrame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	Kit.label(
		"Daily",
		list,
		Text.get("QUEST_DAILY"),
		{ Size = UDim2.new(1, 0, 0, 30), TextColor3 = Kit.GOLD, LayoutOrder = 0 }
	)
	for i, state in data.quests.daily do
		questRow(list, state, i)
	end
	Kit.label(
		"Weekly",
		list,
		Text.get("QUEST_WEEKLY"),
		{ Size = UDim2.new(1, 0, 0, 30), TextColor3 = Kit.GOLD, LayoutOrder = 10 }
	)
	for i, state in data.quests.weekly do
		questRow(list, state, 10 + i)
	end
end

local function renderCues(data: Progression.PlayerData, list: ScrollingFrame)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	for i, cue in Cues.List do
		local row = card(list, i)
		row.Size = UDim2.new(1, -8, 0, 64)
		Kit.label("Name", row, Text.get(cue.nameKey), {
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(0.6, 0, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Kit.GOLD,
		})
		Kit.label(
			"Stats",
			row,
			Text.format("CUE_STATS", {
				aim = string.format("%.2f", cue.aim),
				spin = math.round(cue.spin * 100),
				power = math.round(cue.power * 100),
				time = cue.time,
			}),
			{
				Position = UDim2.fromOffset(12, 32),
				Size = UDim2.new(0.7, 0, 0, 26),
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}
		)
		local owned = data.cosmetics.cues[cue.id] == true
		local equipped = data.equipped.cue == cue.id
		local key = if equipped then "CUE_EQUIPPED" elseif owned then "CUE_EQUIP" else "CUE_BUY"
		local b = Kit.button("Action", row, key, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(150, 44),
			BackgroundColor3 = if equipped then Kit.GREY else Kit.RED,
		}, function()
			if owned then
				Remotes.Event("EquipCue"):FireServer(cue.id)
			else
				Remotes.Event("BuyCue"):FireServer(cue.id)
			end
		end)
		if not owned then
			b.Text = Text.format("CUE_BUY", { price = cue.price })
		end
	end
end

local RENDERERS: { [Page]: (Progression.PlayerData, ScrollingFrame) -> () } = {
	Spirits = renderSpirits,
	Daily = renderDaily,
	Quests = renderQuests,
	Cues = renderCues,
}

local function refresh()
	local data = PlayerDataController.get()
	if not data then
		return
	end
	coinsLabel.Text = `💰 {data.coins}`
	gemsLabel.Text = `💎 {data.gems}`
	levelLabel.Text = Text.format("MENU_LEVEL", { level = data.level })
	local page: Page? = open
	if page then
		local entry = panels[page]
		Kit.clear(entry.list)
		for _, child in entry.list:GetChildren() do
			if child:IsA("UIGridLayout") or child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		RENDERERS[page](data, entry.list)
	end
end

local function show(page: Page?)
	for name, entry in panels do
		entry.panel.Visible = name == page
	end
	if page then
		for _, other in extraPanels do
			other.Visible = false
		end
	end
	open = page
	refresh()
end

-- Adds a menu button for a later phase's screen (dojo, shop). `panel` is closed when another opens.
function MenuController.addButton(key: string, order: number, onActivated: () -> (), panel: GuiObject?)
	if panel then
		table.insert(extraPanels, panel)
	end
	Kit.button(key, menuButtons, key, { Size = UDim2.fromOffset(130, 46), LayoutOrder = order }, function()
		show(nil)
		for _, other in extraPanels do
			other.Visible = false
		end
		onActivated()
	end)
end

function MenuController.Init()
	gui = Kit.screen("Menu", 2)
	local bar = Kit.frame("Currency", gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -110, 0, 8),
		Size = UDim2.fromOffset(330, 40),
	})
	Kit.corner(bar, 0.3)
	currencyBar = bar
	levelLabel = Kit.label("Level", bar, "", { Size = UDim2.fromScale(0.3, 1), TextColor3 = Kit.GOLD })
	coinsLabel = Kit.label("Coins", bar, "", { Position = UDim2.fromScale(0.3, 0), Size = UDim2.fromScale(0.38, 1) })
	gemsLabel = Kit.label("Gems", bar, "", { Position = UDim2.fromScale(0.68, 0), Size = UDim2.fromScale(0.32, 1) })

	menuButtons = Kit.frame("Buttons", gui, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 16, 1, -16),
		Size = UDim2.fromOffset(276, 270),
		BackgroundTransparency = 1,
	})
	-- Two columns of five: one tall column reached up under the Roblox chat window, which eats clicks.
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(130, 46)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.FillDirectionMaxCells = 5
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = menuButtons
	local pages: { { page: Page, key: string } } = {
		{ page = "Spirits", key = "MENU_SPIRITS" },
		{ page = "Daily", key = "MENU_DAILY" },
		{ page = "Quests", key = "MENU_QUESTS" },
		{ page = "Cues", key = "MENU_CUES" },
	}
	for i, entry in pages do
		local page: Page = entry.page
		local key = entry.key
		local panel, list = Kit.panel(page, gui, key, function()
			show(nil)
		end)
		panels[page] = { panel = panel, list = list }
		Kit.button(page, menuButtons, key, { Size = UDim2.fromOffset(130, 46), LayoutOrder = i }, function()
			show(if open == page then nil else page)
		end)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Invite friends: the invite carries our user id so the server can reward us when they join.
local function invite()
	local player = Players.LocalPlayer
	pcall(function()
		if SocialService:CanSendGameInviteAsync(player) then
			local options = Instance.new("ExperienceInviteOptions")
			options.LaunchData = tostring(player.UserId)
			SocialService:PromptGameInvite(player, options)
		end
	end)
end

-- Codes: a text box only the player sees; the server checks the code against its list.
local function buildCodes()
	local panel = Kit.frame("Codes", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(360, 170),
		Visible = false,
		Active = true,
		ZIndex = 2,
	})
	Kit.corner(panel, 0.08)
	local box = Instance.new("TextBox")
	box.Name = "Code"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 20)
	box.Size = UDim2.fromOffset(300, 48)
	box.Font = Enum.Font.GothamBold
	box.TextSize = 22
	box.PlaceholderText = Text.get("CODE_PLACEHOLDER")
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = panel
	Kit.button("Redeem", panel, "CODE_REDEEM", {
		Position = UDim2.fromOffset(30, 90),
		Size = UDim2.fromOffset(140, 48),
	}, function()
		Remotes.Event("RedeemCode"):FireServer(box.Text)
		box.Text = ""
	end)
	Kit.button("CloseCodes", panel, "MENU_CLOSE", {
		Position = UDim2.fromOffset(190, 90),
		Size = UDim2.fromOffset(140, 48),
		BackgroundColor3 = Kit.GREY,
	}, function()
		panel.Visible = false
	end)
	MenuController.addButton("MENU_CODES", 20, function()
		panel.Visible = true
	end, panel)
end

function MenuController.Start()
	MenuController.addButton("MENU_INVITE", 19, invite)
	buildCodes()
	PlayerDataController.Changed:Connect(refresh)
	TableViewController.SeatChanged:Connect(function(tableId)
		menuButtons.Visible = tableId == nil
		currencyBar.Visible = tableId == nil -- at the table it would cover the match status panel
		if tableId then
			show(nil)
		end
	end)
end

return MenuController
