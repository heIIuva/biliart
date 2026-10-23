--!strict
-- Game passes and developer products (GDD 13). The ONLY MarketplaceService.ProcessReceipt in the
-- game lives here. A receipt is granted at most once (purchase ids kept in the profile) and only
-- while the buyer's profile is active; otherwise NotProcessedYet so Roblox retries later.
-- Rewarded ads arrive here as receipts too (ProductPurchaseChannel.AdReward).
-- REMINDER: no random paid items. If one is ever added: show odds (sum 100%) before purchase and
-- check PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Monetization = require(Shared.Config.Monetization)
local RateLimiter = require(Shared.Util.RateLimiter)
local Remotes = require(Shared.Net.Remotes)
local Shop = require(Shared.Game.Shop)
local DataService = require(script.Parent.DataService)

local GIFT_SECONDS = 120 -- a gift target is remembered this long before the purchase prompt closes

local owned: { [Player]: { [string]: boolean } } = {}
local gifts: { [Player]: { key: string, recipient: number, expires: number } } = {}
local adRewardHandlers: { [string]: (Player) -> () } = {}
local limiter = RateLimiter.new(1, 3)
local serverHypeUntil = 0

local ShopService = {}

function ShopService.owns(player: Player, passKey: string): boolean
	local cache = owned[player]
	return cache ~= nil and cache[passKey] == true
end

-- Registers the effect of a rewarded-ad product that needs game context (x2 match reward, …).
function ShopService.onAdReward(placement: string, handler: (Player) -> ())
	adRewardHandlers[placement] = handler
end

function ShopService.serverHypeActive(): boolean
	return os.time() < serverHypeUntil
end

-- Multiplier for match coins: VIP, coin boost and the server hype each double it.
function ShopService.coinMultiplier(player: Player): number
	local data = DataService.get(player)
	local multiplier = 1
	if ShopService.owns(player, "VIP") then
		multiplier *= 2
	end
	if data and Shop.boostActive(data.boosts, "Coins", os.time()) then
		multiplier *= 2
	end
	if ShopService.serverHypeActive() then
		multiplier *= 2
	end
	return multiplier
end

function ShopService.dojoMultiplier(player: Player): number
	local data = DataService.get(player)
	local multiplier = 1
	if ShopService.owns(player, "DojoX2") then
		multiplier *= 2
	end
	if ShopService.owns(player, "TigerTable") then
		multiplier *= 1 + Monetization.TigerTableBonus
	end
	if data and Shop.boostActive(data.boosts, "Dojo", os.time()) then
		multiplier *= 2
	end
	return multiplier
end

local function sendState(player: Player?)
	local passes: { [string]: boolean } = if player then owned[player] or {} else {}
	local state = { passes = passes, serverHypeUntil = serverHypeUntil }
	if player then
		Remotes.Event("ShopState"):FireClient(player, state)
	else
		for _, p in Players:GetPlayers() do
			Remotes.Event("ShopState"):FireClient(p, { passes = owned[p] or {}, serverHypeUntil = serverHypeUntil })
		end
	end
end

-- Applies a product to `target` (the buyer, or a gift recipient who is online).
local function grant(buyer: Player, target: Player, product: Monetization.Product, viaAd: boolean)
	local data = DataService.get(target)
	if not data then
		return
	end
	if product.coins then
		DataService.addCurrency(target, "coins", product.coins, "IAP", product.key)
		DataService.notify(target, "NOTIFY_COINS", { amount = product.coins })
	end
	if product.gems then
		DataService.addCurrency(target, "gems", product.gems, "IAP", product.key)
		DataService.notify(target, "NOTIFY_GEMS", { amount = product.gems })
	end
	if product.boost and product.minutes then
		Shop.extendBoost(data.boosts, product.boost, product.minutes, os.time())
		DataService.notify(target, "SHOP_BOOST_ON", { minutes = product.minutes })
	end
	local cosmetic = product.cosmetic
	if cosmetic then
		local category = (data.cosmetics :: any)[cosmetic.category]
		if category then
			category[cosmetic.id] = true
		end
	end
	if product.once then
		data.purchases.starterPack = true
	end
	if product.serverHype and product.minutes then
		serverHypeUntil = math.max(serverHypeUntil, os.time()) + product.minutes * 60
		Remotes.Event("Announcement")
			:FireAllClients({ playerName = buyer.DisplayName, titleId = "SERVER_HYPE", crossServer = false })
		sendState(nil)
	end
	if viaAd and product.adReward then
		local handler = adRewardHandlers[product.adReward]
		if handler then
			handler(target)
		end
	end
	if target ~= buyer then
		DataService.notify(target, "SHOP_GIFT_RECEIVED", { from = buyer.DisplayName })
		DataService.notify(buyer, "SHOP_GIFT_SENT", { to = target.DisplayName })
	end
	DataService.changed(target)
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local buyer = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = if buyer then DataService.get(buyer) else nil
	if not buyer or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if Shop.seenReceipt(data.purchases.recentReceiptIds, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Shop.productById(receipt.ProductId)
	if not product then
		warn(`[Shop] unknown product {receipt.ProductId}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local viaAd = receipt.ProductPurchaseChannel == Enum.ProductPurchaseChannel.AdReward

	local gift = gifts[buyer]
	if gift and gift.key == product.key and os.clock() < gift.expires and product.giftable then
		gifts[buyer] = nil
		local recipient = Players:GetPlayerByUserId(gift.recipient)
		if recipient and DataService.get(recipient) then
			grant(buyer, recipient, product, false)
		else
			-- Recipient left: deliver through their saved data.
			DataService.message(gift.recipient, { kind = "Gift", product = product.key, from = buyer.DisplayName })
			DataService.notify(buyer, "SHOP_GIFT_SENT", { to = tostring(gift.recipient) })
		end
	else
		grant(buyer, buyer, product, viaAd)
	end
	Shop.rememberReceipt(data.purchases.recentReceiptIds, purchaseId)
	DataService.changed(buyer)
	DataService.save(buyer)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local function refreshPasses(player: Player)
	local cache = {}
	for _, pass in Monetization.Passes do
		if pass.id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			cache[pass.key] = ok and has == true
		end
	end
	owned[player] = cache
	sendState(player)
end

local function onBuy(player: Player, payload: unknown)
	local data = DataService.get(player)
	if not limiter:Allow(player) or not data or type(payload) ~= "table" then
		return
	end
	local raw = payload :: { [unknown]: unknown }
	if raw.kind == "pass" and type(raw.key) == "string" then
		local pass = Shop.passByKey(raw.key)
		if not pass or pass.id == 0 then
			DataService.notify(player, "SHOP_NOT_CONFIGURED")
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	elseif raw.kind == "product" and type(raw.key) == "string" then
		local product = Shop.productByKey(raw.key)
		if not product or product.id == 0 or product.hidden then
			DataService.notify(player, "SHOP_NOT_CONFIGURED")
			return
		end
		if product.once and data.purchases.starterPack then
			return
		end
		local recipient = tonumber(raw.giftTo)
		if recipient and recipient ~= player.UserId and product.giftable and Players:GetPlayerByUserId(recipient) then
			gifts[player] = { key = product.key, recipient = recipient, expires = os.clock() + GIFT_SECONDS }
		else
			gifts[player] = nil
		end
		MarketplaceService:PromptProductPurchase(player, product.id)
	end
end

function ShopService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for _, pass in Monetization.Passes do
			if pass.id == passId then
				local cache = owned[player] or {}
				cache[pass.key] = true
				owned[player] = cache
				DataService.notify(player, "SHOP_PASS_ON")
				sendState(player)
			end
		end
	end)
	DataService.Message:Connect(function(player, message)
		if message.kind == "Gift" and type(message.product) == "string" then
			local product = Shop.productByKey(message.product)
			if product then
				grant(player, player, product, false)
				DataService.notify(player, "SHOP_GIFT_RECEIVED", { from = tostring(message.from) })
			end
		end
	end)
	Players.PlayerAdded:Connect(refreshPasses)
	for _, player in Players:GetPlayers() do
		task.spawn(refreshPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		gifts[player] = nil
		limiter:Forget(player)
	end)
	Remotes.Event("Buy").OnServerEvent:Connect(onBuy)
end

return ShopService
