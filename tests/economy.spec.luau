--!strict
-- Progression and economy formulas.
local Economy = require("../src/shared/Config/Economy")
local Progression = require("../src/shared/Game/Progression")
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
}
