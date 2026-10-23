--!strict
-- Shop (GDD 13): game passes, gems/coins packs, boosts, server hype, skins and gifts to players on
-- the server. Robux purchases are prompted by the server; rewards are granted in ProcessReceipt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Monetization = require(Shared.Config.Monetization)
local Remotes = require(Shared.Net.Remotes)
local Text = require(Shared.Util.Text)
local Kit = require(script.Parent.Parent.UI.Kit)
local MenuController = require(script.Parent.MenuController)
local PlayerDataController = require(script.Parent.PlayerDataController)

local panel: Frame
local list: ScrollingFrame
local passes: { [string]: boolean } = {}
local giftTo: Player? = nil
local giftLabel: TextButton

local ShopController = {
	serverHypeUntil = 0,
}

local function row(order: number, nameKey: string, buttonKey: string, enabled: boolean, onActivated: () -> ())
	local f = Kit.frame(
		"Row",
		list,
		{ LayoutOrder = order, Size = UDim2.new(1, -8, 0, 54), BackgroundColor3 = Color3.fromRGB(45, 30, 24) }
	)
	Kit.corner(f, 0.08)
	Kit.label("Name", f, Text.get(nameKey), {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromScale(0.65, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})
	Kit.button("Action", f, buttonKey, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(150, 40),
		BackgroundColor3 = if enabled then Kit.RED else Kit.GREY,
	}, function()
		if enabled then
			onActivated()
		end
	end)
end

local function render()
	if not panel.Visible then
		return
	end
	local data = PlayerDataController.get()
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
	Kit.label(
		"Passes",
		list,
		Text.get("SHOP_PASSES"),
		{ LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 30), TextColor3 = Kit.GOLD }
	)
	for i, pass in Monetization.Passes do
		local owned = passes[pass.key] == true
		row(i, pass.nameKey, if owned then "SHOP_OWNED" else "SHOP_BUY", not owned, function()
			Remotes.Event("Buy"):FireServer({ kind = "pass", key = pass.key })
		end)
	end
	Kit.label(
		"Products",
		list,
		Text.get("SHOP_PRODUCTS"),
		{ LayoutOrder = 50, Size = UDim2.new(1, 0, 0, 30), TextColor3 = Kit.GOLD }
	)
	local order = 50
	for _, product in Monetization.Products do
		if product.hidden or (product.once and data and (data :: any).starterPackBought) then
			continue
		end
		order += 1
		local gift = giftTo
		local key = if gift and product.giftable then "SHOP_GIFT" else "SHOP_BUY"
		row(order, product.nameKey, key, true, function()
			Remotes.Event("Buy"):FireServer({
				kind = "product",
				key = product.key,
				giftTo = if gift and product.giftable then gift.UserId else nil,
			})
		end)
	end
end

-- Cycles the gift recipient through the other players on the server (nil = buy for myself).
local function nextRecipient()
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= Players.LocalPlayer then
			table.insert(others, p)
		end
	end
	local index = if giftTo then table.find(others, giftTo) else nil
	giftTo = if index then others[index + 1] else others[1]
	giftLabel.Text = if giftTo
		then Text.format("SHOP_GIFT_TO", { name = giftTo.DisplayName })
		else Text.get("SHOP_GIFT")
	render()
end

function ShopController.Init()
	local gui = Kit.screen("Shop", 3)
	local frame, scroll = Kit.panel("ShopPanel", gui, "SHOP_TITLE", function()
		panel.Visible = false
	end)
	panel, list = frame, scroll
	local giftButton = Kit.button("GiftTarget", panel, "SHOP_GIFT", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -130, 0, 8),
		Size = UDim2.fromOffset(220, 40),
		BackgroundColor3 = Color3.fromRGB(120, 80, 20),
	}, nextRecipient)
	giftLabel = giftButton
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ShopController.Start()
	MenuController.addButton("MENU_SHOP", 6, function()
		panel.Visible = true
		render()
	end, panel)
	Remotes.Event("ShopState").OnClientEvent
		:Connect(function(state: { passes: { [string]: boolean }, serverHypeUntil: number })
			passes = state.passes
			ShopController.serverHypeUntil = state.serverHypeUntil
			render()
		end)
	PlayerDataController.Changed:Connect(render)
	Players.PlayerRemoving:Connect(function(p)
		if p == giftTo then
			giftTo = nil
			giftLabel.Text = Text.get("SHOP_GIFT")
		end
	end)
end

return ShopController
