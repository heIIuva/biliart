--!strict
-- Shop rules as pure functions (tested in Lune): product lookup, receipt idempotency, boosts.

local Monetization = require("../Config/Monetization")

local RECEIPT_MEMORY = 50 -- remembered purchase ids per player (receipts can be redelivered)

local Shop = {}

function Shop.productByKey(key: string): Monetization.Product?
	for _, product in Monetization.Products do
		if product.key == key then
			return product
		end
	end
	return nil
end

function Shop.productById(id: number): Monetization.Product?
	if id == 0 then
		return nil
	end
	for _, product in Monetization.Products do
		if product.id == id then
			return product
		end
	end
	return nil
end

function Shop.passByKey(key: string): Monetization.Pass?
	for _, pass in Monetization.Passes do
		if pass.key == key then
			return pass
		end
	end
	return nil
end

-- True if this purchase was already granted (ProcessReceipt can run again for the same receipt).
function Shop.seenReceipt(ids: { string }, purchaseId: string): boolean
	return table.find(ids, purchaseId) ~= nil
end

-- Remembers a granted purchase, keeping only the most recent ids.
function Shop.rememberReceipt(ids: { string }, purchaseId: string)
	table.insert(ids, purchaseId)
	while #ids > RECEIPT_MEMORY do
		table.remove(ids, 1)
	end
end

-- Boosts extend: a second purchase adds time instead of stacking the multiplier.
function Shop.extendBoost(boosts: { [string]: number }, kind: string, minutes: number, now: number)
	boosts[kind] = math.max(boosts[kind] or 0, now) + minutes * 60
end

function Shop.boostActive(boosts: { [string]: number }, kind: string, now: number): boolean
	return (boosts[kind] or 0) > now
end

return Shop
