--!strict
-- Dojo screen (GDD 11): income, till, tables to buy/upgrade, decor, rebirth; "while you were away"
-- popup for offline earnings; idle animation of the NPC students on every plot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Dojo = require(Shared.Config.Dojo)
local DojoMath = require(Shared.Game.Dojo)
local Progression = require(Shared.Game.Progression)
local Remotes = require(Shared.Net.Remotes)
local ShotClassifier = require(Shared.Pool.ShotClassifier)
local Text = require(Shared.Util.Text)
local Kit = require(script.Parent.Parent.UI.Kit)
local AdController = require(script.Parent.AdController)
local MenuController = require(script.Parent.MenuController)
local PlayerDataController = require(script.Parent.PlayerDataController)

local panel: Frame
local list: ScrollingFrame
local header: TextLabel
local offline: Frame
local offlineText: TextLabel
local cash, income = 0, 0

local DojoController = {}

local function row(order: number, text: string, buttonText: string?, enabled: boolean, onActivated: () -> ())
	local f = Kit.frame(
		"Row",
		list,
		{ LayoutOrder = order, Size = UDim2.new(1, -8, 0, 56), BackgroundColor3 = Color3.fromRGB(45, 30, 24) }
	)
	Kit.corner(f, 0.08)
	Kit.label("Text", f, text, {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromScale(0.62, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	if buttonText then
		local b = Kit.button("Action", f, "DOJO_MAX", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(190, 42),
			BackgroundColor3 = if enabled then Kit.RED else Kit.GREY,
		}, onActivated)
		b.Text = buttonText
	end
end

local function render()
	local data = PlayerDataController.get()
	if not data or not panel.Visible then
		return
	end
	header.Text = Text.format("DOJO_INCOME", { income = string.format("%.1f", income), cash = math.floor(cash) })
	Kit.clear(list)
	for _, child in list:GetChildren() do
		if child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for i, slot in Dojo.Tables do
		local level = data.dojo.tables[slot.id] or 0
		local cost = DojoMath.upgradeCost(slot, level)
		local text = Text.format("DOJO_TABLE", { n = i, level = level })
		local button = if cost
			then Text.format(if level == 0 then "DOJO_BUY" else "DOJO_UPGRADE", { price = cost })
			else Text.get("DOJO_MAX")
		row(i, text, button, cost ~= nil and data.coins >= cost, function()
			Remotes.Event("DojoAction"):FireServer({ action = "buy", id = slot.id })
		end)
	end
	Kit.label(
		"Decor",
		list,
		Text.get("DOJO_DECOR"),
		{ LayoutOrder = 20, Size = UDim2.new(1, 0, 0, 30), TextColor3 = Kit.GOLD }
	)
	for i, decor in Dojo.Decor do
		local owned = (data.dojo.upgrades[decor.id] or 0) > 0
		row(
			20 + i,
			Text.get(decor.nameKey),
			if owned then Text.get("DOJO_OWNED") else Text.format("DOJO_BUY", { price = decor.price }),
			not owned and data.coins >= decor.price,
			function()
				Remotes.Event("DojoAction"):FireServer({ action = "decor", id = decor.id })
			end
		)
	end

	local need = DojoMath.rebirthRequirement(data.dojo.rebirths)
	local titles = {}
	for titleId, count in need.titles do
		local title = ShotClassifier.byId(titleId)
		table.insert(titles, `{if title then Text.get(title.nameKey) else titleId} x{count}`)
	end
	local titleText = table.concat(titles, ", ") .. (if need.ranked then " " .. Text.get("DOJO_REBIRTH_RANKED") else "")
	Kit.label(
		"Rebirth",
		list,
		Text.get("DOJO_REBIRTH"),
		{ LayoutOrder = 40, Size = UDim2.new(1, 0, 0, 30), TextColor3 = Kit.GOLD }
	)
	local ready = DojoMath.canRebirth(data)
	row(
		41,
		Text.format("DOJO_REBIRTH_INFO", {
			bonus = math.round(Dojo.RebirthBonus * 100),
			coins = need.coins,
			titles = titleText,
		}),
		Text.get("DOJO_REBIRTH_BUTTON"),
		ready,
		function()
			if ready then
				Remotes.Event("DojoAction"):FireServer({ action = "rebirth" })
			end
		end
	)
end

local function buildOffline(gui: ScreenGui)
	offline = Kit.frame("Offline", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 230),
		Visible = false,
		Active = true,
	})
	Kit.corner(offline, 0.06)
	Kit.label(
		"Title",
		offline,
		Text.get("OFFLINE_TITLE"),
		{ Size = UDim2.new(1, 0, 0, 56), TextSize = 26, TextColor3 = Kit.GOLD }
	)
	offlineText = Kit.label(
		"Text",
		offline,
		"",
		{ Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 50), TextSize = 20 }
	)
	Kit.button(
		"Claim",
		offline,
		"OFFLINE_CLAIM",
		{ Position = UDim2.fromOffset(30, 140), Size = UDim2.fromOffset(170, 52) },
		function()
			offline.Visible = false
			Remotes.Event("DojoAction"):FireServer({ action = "claimOffline" })
		end
	)
	local double = Kit.button("Double", offline, "OFFLINE_DOUBLE_AD", {
		Position = UDim2.fromOffset(220, 140),
		Size = UDim2.fromOffset(170, 52),
		BackgroundColor3 = Color3.fromRGB(120, 80, 20),
		Visible = false,
	}, function()
		offline.Visible = false
		AdController.request("OfflineX2")
	end)
	double.Name = "DoubleAd"
end

local function animateStudent(part: Instance)
	if part:IsA("BasePart") and part:GetAttribute("Student") then
		local bob = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		TweenService:Create(part, bob, { CFrame = part.CFrame * CFrame.Angles(math.rad(-20), 0, 0) }):Play()
	end
end

function DojoController.Init()
	local gui = Kit.screen("Dojo", 3)
	local frame, scroll = Kit.panel("DojoPanel", gui, "DOJO_TITLE", function()
		panel.Visible = false
	end)
	panel, list = frame, scroll
	list.Position = UDim2.fromOffset(12, 110)
	list.Size = UDim2.new(1, -24, 1, -122)
	header = Kit.label("Income", panel, "", {
		Position = UDim2.fromOffset(16, 56),
		Size = UDim2.new(0.6, 0, 0, 40),
		TextColor3 = Kit.GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	Kit.button("Visit", panel, "DOJO_VISIT", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 58),
		Size = UDim2.fromOffset(200, 40),
	}, function()
		panel.Visible = false
		Remotes.Event("DojoAction"):FireServer({ action = "visit" })
	end)
	buildOffline(gui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function DojoController.Start()
	local boostAd = Kit.button("BoostAd", panel, "AD_DOJO_BOOST", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -220, 0, 58),
		Size = UDim2.fromOffset(300, 40),
		BackgroundColor3 = Color3.fromRGB(120, 80, 20),
		Visible = false,
	}, function()
		AdController.request("DojoBoost")
	end)
	MenuController.addButton("MENU_DOJO", 5, function()
		panel.Visible = true
		boostAd.Visible = false
		AdController.whenAvailable("DojoBoost", boostAd, function()
			boostAd.Visible = true
		end)
		Remotes.Event("DojoAction"):FireServer({ action = "open" })
		render()
	end)
	Remotes.Event("DojoTick").OnClientEvent:Connect(function(tick: { cash: number, income: number })
		cash, income = tick.cash, tick.income
		if panel.Visible then
			header.Text =
				Text.format("DOJO_INCOME", { income = string.format("%.1f", income), cash = math.floor(cash) })
		end
	end)
	Remotes.Event("OfflineEarnings").OnClientEvent:Connect(function(earned: { amount: number, seconds: number })
		offlineText.Text = Text.format("OFFLINE_EARNED", { amount = earned.amount })
		offline.Visible = true
		local double = offline:FindFirstChild("DoubleAd") :: TextButton
		double.Visible = false
		AdController.whenAvailable("OfflineX2", double, function()
			double.Visible = true
		end)
	end)
	PlayerDataController.Changed:Connect(function(_data: Progression.PlayerData)
		render()
	end)
	local function watch(folder: Instance)
		for _, d in folder:GetDescendants() do
			animateStudent(d)
		end
		folder.DescendantAdded:Connect(animateStudent)
	end
	local folder = Workspace:FindFirstChild("Dojos")
	if folder then
		watch(folder)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Dojos" then
			watch(child)
		end
	end)
end

return DojoController
