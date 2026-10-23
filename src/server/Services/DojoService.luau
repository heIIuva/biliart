--!strict
-- Idle dojo (GDD 11): every player on the server gets a plot with their tables, NPC students, a
-- till and decor. Income accrues every second into the till; the owner collects it at the till.
-- Offline income is paid on return (capped). Rebirth ("New Year") resets the dojo for a permanent
-- multiplier. Other services add income multipliers / offline caps through the hook functions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Dojo = require(Shared.Config.Dojo)
local DojoMath = require(Shared.Game.Dojo)
local Progression = require(Shared.Game.Progression)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local AnalyticsService = require(script.Parent.AnalyticsService)
local DataService = require(script.Parent.DataService)
local KingTableService = require(script.Parent.KingTableService)
local LeaderboardService = require(script.Parent.LeaderboardService)

local LOBBY_CENTER = Vector3.new(0, 0, -15)
local TABLE_SPACING = 9

local plots: { [number]: Player } = {} -- plot index -> owner
local models: { [Player]: Model } = {}
local plotOf: { [Player]: number } = {}
local lastIncome: { [Player]: number } = {}
local multiplierSources: { (Player) -> number } = {}
local offlineCapSources: { (Player) -> number } = {}
local limiter = RateLimiter.new(3, 6)
local folder: Folder

local DojoService = {}

-- Extra income multiplier from another system (game pass, boost, event). Multiplied together.
function DojoService.addMultiplierSource(source: (Player) -> number)
	table.insert(multiplierSources, source)
end

-- Offline cap in hours from another system (VIP); the largest one wins.
function DojoService.addOfflineCapSource(source: (Player) -> number)
	table.insert(offlineCapSources, source)
end

function DojoService.income(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	local extra = if KingTableService.isKing(player) then 1 + Dojo.KingBonus else 1
	for _, source in multiplierSources do
		extra *= source(player)
	end
	return DojoMath.incomePerSecond(data, extra)
end

local function plotCFrame(index: number): CFrame
	local angle = (index - 1) / Dojo.PlotCount * 2 * math.pi
	local position = LOBBY_CENTER + Vector3.new(math.cos(angle), 0, math.sin(angle)) * Dojo.PlotRingRadius
	return CFrame.lookAt(position, Vector3.new(LOBBY_CENTER.X, 0, LOBBY_CENTER.Z))
end

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function build(player: Player)
	local data = DataService.get(player)
	local index = plotOf[player]
	if not data or not index then
		return
	end
	local old = models[player]
	if old then
		old:Destroy()
	end
	local origin = plotCFrame(index)
	local model = Instance.new("Model")
	model.Name = `Dojo_{player.UserId}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Owner", player.UserId)
	local floor = part(
		"Floor",
		Vector3.new(Dojo.PlotSize, 1, Dojo.PlotSize),
		origin * CFrame.new(0, 0.5, 0),
		Color3.fromRGB(110, 25, 25),
		model,
		Enum.Material.WoodPlanks
	)
	model.PrimaryPart = floor

	-- Sign with the owner's name.
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(240, 50)
	sign.StudsOffset = Vector3.new(0, 10, 0)
	sign.Adornee = floor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(240, 190, 60)
	label.Text = `{player.DisplayName} 道场`
	label.Parent = sign
	sign.Parent = floor

	-- Tables in a 3 x 2 grid, each with a student.
	for i, slot in Dojo.Tables do
		local level = data.dojo.tables[slot.id] or 0
		if level > 0 then
			local col, row = (i - 1) % 3 - 1, (i - 1) // 3
			local at = origin * CFrame.new(col * TABLE_SPACING, 1, -4 + row * 10)
			part(
				"Table",
				Vector3.new(6, 2.5, 3.5),
				at * CFrame.new(0, 1.25, 0),
				Color3.fromRGB(28, 110, 64),
				model,
				Enum.Material.Fabric
			)
			local student = part(
				"Student",
				Vector3.new(1.2, 2.4, 1),
				at * CFrame.new(-3.8, 1.2, 0),
				Color3.fromRGB(230, 200, 160),
				model
			)
			student:SetAttribute("Student", true) -- clients animate it
			part("Head", Vector3.new(1, 1, 1), at * CFrame.new(-3.8, 2.9, 0), Color3.fromRGB(240, 210, 170), model)
			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromOffset(60, 24)
			tag.StudsOffset = Vector3.new(0, 2.5, 0)
			local levelLabel = Instance.new("TextLabel")
			levelLabel.BackgroundTransparency = 1
			levelLabel.Size = UDim2.fromScale(1, 1)
			levelLabel.TextScaled = true
			levelLabel.TextColor3 = Color3.new(1, 1, 1)
			levelLabel.Text = `Lv {level}`
			levelLabel.Parent = tag
			tag.Parent = student
		end
	end

	-- Decor.
	if (data.dojo.upgrades.Lanterns or 0) > 0 then
		for _, x in { -1, 1 } do
			for _, z in { -1, 1 } do
				local lantern = part(
					"Lantern",
					Vector3.new(1.5, 2, 1.5),
					origin * CFrame.new(x * 15, 9, z * 15),
					Color3.fromRGB(230, 40, 30),
					model,
					Enum.Material.Neon
				)
				lantern.Shape = Enum.PartType.Ball
			end
		end
	end
	if (data.dojo.upgrades.Statues or 0) > 0 then
		for _, x in { -1, 1 } do
			part(
				"Statue",
				Vector3.new(2, 5, 2),
				origin * CFrame.new(x * 14, 3.5, -14),
				Color3.fromRGB(200, 160, 40),
				model,
				Enum.Material.Metal
			)
		end
	end
	if (data.dojo.upgrades.Gong or 0) > 0 then
		local gong = part(
			"Gong",
			Vector3.new(0.4, 5, 5),
			origin * CFrame.new(0, 4, -15) * CFrame.Angles(0, math.pi / 2, 0),
			Color3.fromRGB(210, 150, 40),
			model,
			Enum.Material.Metal
		)
		gong.Shape = Enum.PartType.Cylinder
	end

	-- Till: the owner collects here.
	local till = part(
		"Till",
		Vector3.new(3, 3, 2),
		origin * CFrame.new(0, 2.5, 12),
		Color3.fromRGB(200, 150, 40),
		model,
		Enum.Material.Wood
	)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt:SetAttribute("ActionKey", "DOJO_COLLECT")
	prompt:SetAttribute("ObjectKey", "DOJO_TILL")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.Parent = till
	prompt.Triggered:Connect(function(who)
		if who == player then
			DojoService.collect(player)
		end
	end)

	model.Parent = folder
	models[player] = model
end

function DojoService.collect(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local amount = math.floor(data.dojo.cash)
	if amount <= 0 then
		return
	end
	data.dojo.cash -= amount
	data.dojo.lastCollectTime = os.time()
	DataService.addCurrency(player, "coins", amount, "Gameplay", "DojoCollect")
	DataService.notify(player, "NOTIFY_COINS", { amount = amount })
end

-- Pays the stored offline earnings (x multiplier, e.g. 2 after a rewarded ad).
function DojoService.claimOffline(player: Player, multiplier: number)
	local data = DataService.get(player)
	if not data or data.dojo.pendingOffline <= 0 then
		return
	end
	local amount = math.floor(data.dojo.pendingOffline * multiplier)
	data.dojo.pendingOffline = 0
	DataService.addCurrency(player, "coins", amount, "TimedReward", "OfflineIncome")
	DataService.notify(player, "NOTIFY_COINS", { amount = amount })
end

local function offlineCap(player: Player): number
	local cap = Dojo.OfflineCapHours
	for _, source in offlineCapSources do
		cap = math.max(cap, source(player))
	end
	return cap
end

local function onLoaded(player: Player, data: Progression.PlayerData)
	for index = 1, Dojo.PlotCount do
		if not plots[index] then
			plots[index] = player
			plotOf[player] = index
			break
		end
	end
	build(player)
	local amount, seconds =
		DojoMath.offline(DojoService.income(player), data.lastOnlineTime, os.time(), offlineCap(player))
	if amount > 0 then
		data.dojo.pendingOffline += amount
	end
	if data.dojo.pendingOffline > 0 then
		Remotes.Event("OfflineEarnings"):FireClient(player, { amount = data.dojo.pendingOffline, seconds = seconds })
	end
end

local function onAction(player: Player, payload: unknown)
	local data = DataService.get(player)
	if not limiter:Allow(player) or not data or type(payload) ~= "table" then
		return
	end
	local raw = payload :: { [unknown]: unknown }
	local action, id = raw.action, raw.id
	if action == "buy" and type(id) == "string" then
		local slot = DojoMath.slot(id)
		local level = data.dojo.tables[id] or 0
		local cost = if slot then DojoMath.upgradeCost(slot, level) else nil
		if slot and cost then
			if DataService.addCurrency(player, "coins", -cost, "Shop", `DojoTable_{id}`) then
				data.dojo.tables[id] = level + 1
				build(player)
			else
				DataService.notify(player, "NOTIFY_NOT_ENOUGH")
			end
		end
	elseif action == "decor" and type(id) == "string" then
		local decor = DojoMath.decor(id)
		if decor and (data.dojo.upgrades[id] or 0) == 0 then
			if DataService.addCurrency(player, "coins", -decor.price, "Shop", `DojoDecor_{id}`) then
				data.dojo.upgrades[id] = 1
				build(player)
			else
				DataService.notify(player, "NOTIFY_NOT_ENOUGH")
			end
		end
	elseif action == "rebirth" then
		if DojoMath.canRebirth(data) then
			local spent = data.coins
			DojoMath.rebirth(data)
			AnalyticsService.economy(player, false, "coins", spent, 0, "Gameplay", "Rebirth")
			AnalyticsService.progression(player, "Rebirth", data.dojo.rebirths)
			DataService.notify(player, "DOJO_REBIRTH_DONE", { count = data.dojo.rebirths })
			build(player)
		end
	elseif action == "claimOffline" then
		DojoService.claimOffline(player, 1)
	elseif action == "open" then
		AnalyticsService.funnel(player, AnalyticsService.Funnel.OpenedDojo, "OpenedDojo")
		return
	elseif action == "visit" then
		AnalyticsService.funnel(player, AnalyticsService.Funnel.OpenedDojo, "OpenedDojo")
		local model = models[player]
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and model and model.PrimaryPart and root and not root.Anchored then
			character:PivotTo(model.PrimaryPart.CFrame * CFrame.new(0, 4, 8))
		end
	end
	DataService.changed(player)
end

function DojoService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Dojos"
	folder.Parent = Workspace
	-- Empty plot markers so the ring is visible before anyone joins.
	for index = 1, Dojo.PlotCount do
		local marker = part(
			`Plot{index}`,
			Vector3.new(Dojo.PlotSize, 0.2, Dojo.PlotSize),
			plotCFrame(index) * CFrame.new(0, 0.1, 0),
			Color3.fromRGB(70, 30, 30),
			folder
		)
		marker.Transparency = 0.5
	end
end

function DojoService.Start()
	DataService.Loaded:Connect(onLoaded)
	Remotes.Event("DojoAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		local index = plotOf[player]
		if index then
			plots[index] = nil
		end
		plotOf[player] = nil
		lastIncome[player] = nil
		limiter:Forget(player)
		local model = models[player]
		if model then
			model:Destroy()
			models[player] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			for player in plotOf do
				local data = DataService.get(player)
				if data then
					local income = DojoService.income(player)
					data.dojo.cash += income
					Remotes.Event("DojoTick"):FireClient(player, { cash = data.dojo.cash, income = income })
					if lastIncome[player] ~= income then
						lastIncome[player] = income
						LeaderboardService.submit("Dojo", player, income)
					end
				end
			end
		end
	end)
end

return DojoService
