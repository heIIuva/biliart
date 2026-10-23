--!strict
-- Progression and economy formulas.
local Economy = require("../src/shared/Config/Economy")
local Progression = require("../src/shared/Game/Progression")
local Shop = require("../src/shared/Game/Shop")
local Dojo = require("../src/shared/Config/Dojo")
local DojoMath = require("../src/shared/Game/Dojo")
local Spirits = require("../src/shared/Config/Spirits")

return {
	["levels: xp curve grows and levelForXp inverts it"] = function()
		assert(Progression.xpForLevel(1) == 100, "level 1 -> 2 costs 100 xp")
		assert(Progression.xpForLevel(4) > Progression.xpForLevel(3), "curve grows")
		assert(Progression.levelForXp(0) == 1 and Progression.levelForXp(99) == 1, "below the first step")
		assert(Progression.levelForXp(100) == 2, "exactly one level")
		local total = 0
		for level = 1, 9 do
			total += Progression.xpForLevel(level)
		end
		assert(Progression.levelForXp(total) == 10 and Progression.levelForXp(total - 1) == 9, "sum of steps")
		assert(Progression.levelForXp(1e12) == Economy.MaxLevel, "capped")
	end,

	["daily reward: streak, same-day block, reset after a gap, 7-day cycle"] = function()
		local daily = { streak = 0, lastClaimDay = -1 }
		local day, state = Progression.claimDaily(daily, 100)
		assert(day == 1 and state.streak == 1, "first claim is day 1")
		local again = Progression.claimDaily(state, 100)
		assert(again == nil, "only once per day")
		local d2, s2 = Progression.claimDaily(state, 101)
		assert(d2 == 2 and s2.streak == 2, "next day continues")
		local d3 = Progression.claimDaily(s2, 103)
		assert(d3 == 1, "a missed day resets the streak")
		local s = { streak = 7, lastClaimDay = 200 }
		local d8 = Progression.claimDaily(s, 201)
		assert(d8 == 1, "day 8 starts a new cycle")
	end,

	["spirits: thresholds and title mapping"] = function()
		assert(Progression.spiritLevel(0) == 0, "locked")
		assert(Progression.spiritLevel(1) == 1 and Progression.spiritLevel(4) == 1, "level 1")
		assert(Progression.spiritLevel(5) == 2 and Progression.spiritLevel(150) == #Spirits.Thresholds, "levels")
		assert(table.find(Progression.spiritsFor("WHIRLWIND"), "Monkey"), "secret title feeds Monkey")
		assert(#Progression.spiritsFor("SHAME") == 0, "anti-titles feed no spirit")
	end,

	["quests: deterministic picks, refresh per period, progress and caps"] = function()
		local a, b = Progression.template(), Progression.template()
		local time = 20000 * 86400 + 3600
		assert(Progression.refreshQuests(a, 42, time) and Progression.refreshQuests(b, 42, time), "assigned")
		assert(#a.quests.daily == 3 and #a.quests.weekly == 3, "three each")
		for i = 1, 3 do
			assert(a.quests.daily[i].id == b.quests.daily[i].id, "same player, same day, same quests")
		end
		local seen = {}
		for _, q in a.quests.daily do
			assert(not seen[q.id], "no duplicates")
			seen[q.id] = true
		end
		assert(not Progression.refreshQuests(a, 42, time + 60), "same day: no refresh")
		assert(Progression.refreshQuests(a, 42, time + 86400), "next day: refresh")

		local data = Progression.template()
		data.quests.daily =
			{ { id = "d_win1", progress = 0, claimed = false }, { id = "d_tiger", progress = 0, claimed = false } }
		data.quests.weekly = {}
		assert(Progression.questEvent(data, "wins"), "win counts")
		assert(not Progression.questEvent(data, "wins"), "capped at target")
		assert(not Progression.questEvent(data, "title", "CARP"), "wrong title")
		assert(Progression.questEvent(data, "title", "TIGER"), "right title")
	end,

	["data: migration fills new fields and keeps old values"] = function()
		local old: { [string]: any } = { coins = 777, stats = { wins = 3 }, settings = { music = 0 } }
		local data = Progression.migrate(old)
		assert(data.coins == 777 and data.stats.wins == 3 and data.settings.music == 0, "kept")
		assert(data.stats.losses == 0 and data.settings.sfx == 1 and data.gems == 0, "filled")
		assert(data.cosmetics.cues.Base == true and data.equipped.cue == "Base", "base cue")
		assert(data.schemaVersion == Progression.SCHEMA_VERSION, "version")
	end,

	["match rewards are fixed by level"] = function()
		local coins, xp = Progression.matchReward("Hard", true)
		assert(coins == Economy.MatchRewards.Hard.win and xp == Economy.Xp.Win, "hard win")
		local lossCoins = Progression.matchReward("Easy", false)
		assert(lossCoins == Economy.MatchRewards.Easy.loss, "easy loss")
	end,

	["ranked: Elo moves points from loser to winner, upsets move more"] = function()
		local a, b = Progression.elo(1000, 1000, 1, 32)
		assert(a == 1016 and b == 984, `even match: {a} {b}`)
		local favWin = Progression.elo(1400, 1000, 1, 32)
		local underWin = Progression.elo(1000, 1400, 1, 32)
		assert(favWin - 1400 < underWin - 1000, "an upset gains more")
		local x, y = Progression.elo(1234, 987, 0, 32)
		assert(x + y == 1234 + 987, "zero-sum")
	end,

	["dojo: income formula with tables, spirits, rebirths, decor and extra multipliers"] = function()
		local data = Progression.template()
		assert(DojoMath.incomePerSecond(data, 1) == 0, "no tables, no income")
		data.dojo.tables.T1 = 2 -- base 1 x level 2
		data.dojo.tables.T2 = 1 -- base 3 x level 1
		assert(DojoMath.incomePerSecond(data, 1) == 5, "sum of base x level")
		data.spirits.Tiger = { level = 5, progress = 150, skin = "" }
		data.dojo.rebirths = 2
		data.dojo.upgrades.Lanterns = 1
		local expected = 5 * (1 + 5 * Spirits.DojoBonusPerLevel) * (1 + 2 * Dojo.RebirthBonus) * 1.05 * 2
		assert(math.abs(DojoMath.incomePerSecond(data, 2) - expected) < 1e-9, "multipliers stack")
	end,

	["dojo: costs grow, stop at max level"] = function()
		local slot = DojoMath.slot("T1") :: any
		assert(DojoMath.upgradeCost(slot, 0) == slot.price, "buying costs the price")
		assert((DojoMath.upgradeCost(slot, 3) :: number) > (DojoMath.upgradeCost(slot, 2) :: number), "grows")
		assert(DojoMath.upgradeCost(slot, slot.maxLevel) == nil, "max level")
	end,

	["dojo: offline earnings are capped and safe against bad clocks"] = function()
		local amount, seconds = DojoMath.offline(10, 1000, 1000 + 3600, 8)
		assert(seconds == 3600 and amount == math.floor(10 * Dojo.OfflineRate * 3600), "one hour")
		local _, capped = DojoMath.offline(10, 1000, 1000 + 100 * 3600, 8)
		assert(capped == 8 * 3600, "capped at 8 h")
		assert(DojoMath.offline(10, 5000, 1000, 8) == 0, "clock went back")
		assert(DojoMath.offline(10, 0, 1000, 8) == 0, "first visit")
	end,

	["dojo: rebirth needs coins and titles, resets and raises the multiplier"] = function()
		local data = Progression.template()
		local need = DojoMath.rebirthRequirement(0)
		data.coins = need.coins
		assert(not DojoMath.canRebirth(data), "titles missing")
		for titleId, count in need.titles do
			data.stats.titles[titleId] = count
		end
		assert(DojoMath.canRebirth(data), "requirements met")
		data.dojo.tables.T1 = 5
		DojoMath.rebirth(data)
		assert(data.coins == 0 and data.dojo.tables.T1 == nil and data.dojo.rebirths == 1, "reset")
		local second = DojoMath.rebirthRequirement(1)
		assert(second.ranked, "the second rebirth wants a ranked title")
		data.coins = second.coins
		for titleId, count in second.titles do
			data.stats.titles[titleId] = count
		end
		assert(not DojoMath.canRebirth(data), "casual titles do not count for a ranked requirement")
		local beyond = DojoMath.rebirthRequirement(5)
		assert(beyond.coins > Dojo.Rebirths[#Dojo.Rebirths].coins, "keeps growing")
	end,

	["shop: receipts are idempotent and the memory is bounded"] = function()
		local ids: { string } = {}
		assert(not Shop.seenReceipt(ids, "a"), "new receipt")
		Shop.rememberReceipt(ids, "a")
		assert(Shop.seenReceipt(ids, "a"), "redelivered receipt is recognised")
		for i = 1, 60 do
			Shop.rememberReceipt(ids, `r{i}`)
		end
		assert(#ids == 50 and not Shop.seenReceipt(ids, "a") and Shop.seenReceipt(ids, "r60"), "bounded")
	end,

	["shop: boosts extend instead of stacking, products resolve, placeholder ids never match"] = function()
		local boosts: { [string]: number } = {}
		Shop.extendBoost(boosts, "Coins", 30, 1000)
		assert(boosts.Coins == 1000 + 1800 and Shop.boostActive(boosts, "Coins", 2000), "active")
		Shop.extendBoost(boosts, "Coins", 30, 2000)
		assert(boosts.Coins == 1000 + 3600, "extended from the current end")
		Shop.extendBoost(boosts, "Coins", 10, 10000)
		assert(boosts.Coins == 10000 + 600, "expired boosts restart from now")
		assert(not Shop.boostActive(boosts, "Dojo", 2000), "other kind inactive")
		assert(Shop.productByKey("Starter") and (Shop.productByKey("Starter") :: any).once, "starter pack is one-time")
		assert(Shop.productById(0) == nil, "id 0 is a placeholder")
	end,
}
