--!strict
-- Dojo formulas as pure functions (tested in Lune). See Config/Dojo for the income formula.

local Dojo = require("../Config/Dojo")
local Progression = require("./Progression")
local Spirits = require("../Config/Spirits")

export type Multipliers = { extra: number? } -- product of game pass / boost / event / King multipliers

local DojoMath = {}

function DojoMath.slot(id: string): Dojo.TableSlot?
	for _, slot in Dojo.Tables do
		if slot.id == id then
			return slot
		end
	end
	return nil
end

function DojoMath.decor(id: string): Dojo.Decor?
	for _, decor in Dojo.Decor do
		if decor.id == id then
			return decor
		end
	end
	return nil
end

-- Coins to buy a table (level 0 -> 1) or upgrade it (level n -> n + 1); nil at max level.
function DojoMath.upgradeCost(slot: Dojo.TableSlot, level: number): number?
	if level >= slot.maxLevel then
		return nil
	end
	return math.floor(slot.price * slot.upgradeGrowth ^ level)
end

function DojoMath.spiritLevels(data: Progression.PlayerData): number
	local total = 0
	for _, state in data.spirits do
		total += state.level
	end
	return total
end

function DojoMath.incomePerSecond(data: Progression.PlayerData, extra: number): number
	local base = 0
	for _, slot in Dojo.Tables do
		base += slot.baseIncome * (data.dojo.tables[slot.id] or 0)
	end
	local decor = 0
	for _, item in Dojo.Decor do
		if (data.dojo.upgrades[item.id] or 0) > 0 then
			decor += item.bonus
		end
	end
	return base
		* (1 + DojoMath.spiritLevels(data) * Spirits.DojoBonusPerLevel)
		* (1 + data.dojo.rebirths * Dojo.RebirthBonus)
		* (1 + decor)
		* extra
end

-- Offline earnings for the time since lastOnline, capped; nothing for bad clocks (negative or zero).
function DojoMath.offline(incomePerSecond: number, lastOnline: number, now: number, capHours: number): (number, number)
	if lastOnline <= 0 or now <= lastOnline then
		return 0, 0
	end
	local seconds = math.min(now - lastOnline, capHours * 3600)
	return math.floor(incomePerSecond * Dojo.OfflineRate * seconds), seconds
end

function DojoMath.rebirthRequirement(rebirths: number): Dojo.Rebirth
	local list = Dojo.Rebirths
	if rebirths < #list then
		return list[rebirths + 1]
	end
	local last = list[#list]
	return { coins = last.coins * 2 ^ (rebirths - #list + 1), titles = last.titles, ranked = last.ranked }
end

-- Whether the player meets the next rebirth: coins and titles (in ranked matches if required).
function DojoMath.canRebirth(data: Progression.PlayerData): boolean
	local need = DojoMath.rebirthRequirement(data.dojo.rebirths)
	if data.coins < need.coins then
		return false
	end
	local counts = if need.ranked then data.stats.rankedTitles else data.stats.titles
	for titleId, count in need.titles do
		if (counts[titleId] or 0) < count then
			return false
		end
	end
	return true
end

-- Applies a rebirth: coins and dojo tables/decor reset, the permanent multiplier goes up.
function DojoMath.rebirth(data: Progression.PlayerData)
	data.coins = 0
	data.dojo.tables = {}
	data.dojo.upgrades = {}
	data.dojo.cash = 0
	data.dojo.rebirths += 1
end

return DojoMath
