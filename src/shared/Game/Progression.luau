--!strict
-- Player data schema and progression rules as pure functions (GDD 10): levels, daily reward
-- streak, spirit levels, quest picking and progress, migration of saved data.
-- Pure Luau: no Roblox API (tested in Lune).

local Cues = require("../Config/Cues")
local Economy = require("../Config/Economy")
local Quests = require("../Config/Quests")
local Spirits = require("../Config/Spirits")

export type QuestState = { id: string, progress: number, claimed: boolean }

export type PlayerData = {
	schemaVersion: number,
	coins: number,
	gems: number,
	xp: number,
	level: number,
	trophies: number,
	rating: number,
	stats: { shots: number, pots: number, wins: number, losses: number, titles: { [string]: number } },
	spirits: { [string]: { level: number, progress: number, skin: string } },
	equippedSpirit: string,
	cosmetics: {
		cues: { [string]: boolean },
		tables: { [string]: boolean },
		ballSets: { [string]: boolean },
		announcers: { [string]: boolean },
		emotes: { [string]: boolean },
		splashSkins: { [string]: boolean },
	},
	equipped: { cue: string, table: string, ballSet: string, announcer: string, emote: string, splashSkin: string },
	dojo: {
		tables: { [string]: number }, -- table slot -> level (0 = not bought)
		upgrades: { [string]: number },
		cash: number, -- coins waiting in the dojo till
		lastCollectTime: number,
		rebirths: number,
	},
	daily: { streak: number, lastClaimDay: number },
	quests: { day: number, week: number, daily: { QuestState }, weekly: { QuestState } },
	purchases: { recentReceiptIds: { string }, starterPack: boolean },
	boosts: { [string]: number }, -- boost id -> os.time() it ends
	redeemedCodes: { [string]: boolean },
	groupRewardClaimed: boolean,
	settings: { music: number, sfx: number, announcer: number, quality: string },
	tutorialDone: boolean,
	firstJoinTime: number,
	lastOnlineTime: number,
}

local SCHEMA_VERSION = 1
local DAY = 86400

local Progression = {}

Progression.SCHEMA_VERSION = SCHEMA_VERSION

function Progression.template(): PlayerData
	return {
		schemaVersion = SCHEMA_VERSION,
		coins = Economy.StartingCoins,
		gems = 0,
		xp = 0,
		level = 1,
		trophies = 0,
		rating = 1000,
		stats = { shots = 0, pots = 0, wins = 0, losses = 0, titles = {} },
		spirits = {},
		equippedSpirit = "",
		cosmetics = {
			cues = { [Cues.Base] = true },
			tables = {},
			ballSets = {},
			announcers = {},
			emotes = {},
			splashSkins = {},
		},
		equipped = { cue = Cues.Base, table = "", ballSet = "", announcer = "", emote = "", splashSkin = "" },
		dojo = { tables = {}, upgrades = {}, cash = 0, lastCollectTime = 0, rebirths = 0 },
		daily = { streak = 0, lastClaimDay = -1 },
		quests = { day = -1, week = -1, daily = {}, weekly = {} },
		purchases = { recentReceiptIds = {}, starterPack = false },
		boosts = {},
		redeemedCodes = {},
		groupRewardClaimed = false,
		settings = { music = 0.6, sfx = 1, announcer = 1, quality = "Auto" },
		tutorialDone = false,
		firstJoinTime = 0,
		lastOnlineTime = 0,
	}
end

-- Fills missing fields from the template (recursively) and upgrades old schema versions.
function Progression.migrate(data: { [string]: any }): PlayerData
	local function fill(target: { [string]: any }, defaults: { [string]: any })
		for key, value in defaults do
			if target[key] == nil then
				target[key] = if type(value) == "table" then table.clone(value) else value
			elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
				fill(target[key], value)
			end
		end
	end
	fill(data, Progression.template() :: any)
	-- Future schema steps go here: if data.schemaVersion < 2 then ... end
	data.schemaVersion = SCHEMA_VERSION
	return data :: any
end

-- XP needed to go from `level` to `level + 1`.
function Progression.xpForLevel(level: number): number
	return math.floor(Economy.LevelBase * level ^ Economy.LevelExponent)
end

-- Level for a total amount of XP.
function Progression.levelForXp(xp: number): number
	local level = 1
	while level < Economy.MaxLevel and xp >= Progression.xpForLevel(level) do
		xp -= Progression.xpForLevel(level)
		level += 1
	end
	return level
end

function Progression.dayIndex(time: number): number
	return time // DAY
end

function Progression.weekIndex(time: number): number
	return (time // DAY + 3) // 7 -- weeks start on Monday (1970-01-01 was a Thursday)
end

-- Daily reward: returns the reward day (1..7) and the new streak state, or nil if already claimed.
function Progression.claimDaily(
	daily: { streak: number, lastClaimDay: number },
	today: number
): (number?, { streak: number, lastClaimDay: number })
	if daily.lastClaimDay == today then
		return nil, daily
	end
	local streak = if daily.lastClaimDay == today - 1 then daily.streak + 1 else 1
	local cycle = #Economy.DailyRewards
	local rewardDay = (streak - 1) % cycle + 1
	return rewardDay, { streak = streak, lastClaimDay = today }
end

-- Spirit level for a progress count: 0 = locked, then 1..#Thresholds.
function Progression.spiritLevel(progress: number): number
	local level = 0
	for i, threshold in Spirits.Thresholds do
		if progress >= threshold then
			level = i
		end
	end
	return level
end

-- Spirits fed by a title.
function Progression.spiritsFor(titleId: string): { string }
	local list = {}
	for _, spirit in Spirits.List do
		if table.find(spirit.titles, titleId) then
			table.insert(list, spirit.id)
		end
	end
	return list
end

-- Deterministic pick of `count` quests from a pool for a player and period.
local function pick(pool: { Quests.Quest }, count: number, seed: number): { QuestState }
	local state = seed % 2147483646 + 1
	local indices = {}
	for i = 1, #pool do
		indices[i] = i
	end
	local chosen = {}
	for _ = 1, math.min(count, #pool) do
		state = state * 48271 % 2147483647
		local slot = state % #indices + 1
		local index = table.remove(indices, slot) :: number
		table.insert(chosen, { id = pool[index].id, progress = 0, claimed = false })
	end
	return chosen
end

-- Refreshes daily/weekly quests when a new day/week starts. Returns true if anything changed.
function Progression.refreshQuests(data: PlayerData, userId: number, time: number): boolean
	local day, week = Progression.dayIndex(time), Progression.weekIndex(time)
	local changed = false
	if data.quests.day ~= day then
		data.quests.day = day
		data.quests.daily = pick(Quests.Daily, Quests.PerPeriod, userId * 31 + day)
		changed = true
	end
	if data.quests.week ~= week then
		data.quests.week = week
		data.quests.weekly = pick(Quests.Weekly, Quests.PerPeriod, userId * 17 + week * 7 + 3)
		changed = true
	end
	return changed
end

function Progression.questDef(id: string): Quests.Quest?
	for _, list in { Quests.Daily, Quests.Weekly } do
		for _, quest in list do
			if quest.id == id then
				return quest
			end
		end
	end
	return nil
end

-- Applies a game event to all active quests; returns true if any progress changed.
-- kind: "title" (titleId), "wins", "pots", "spinPots", "matches"; amount defaults to 1.
function Progression.questEvent(data: PlayerData, kind: string, titleId: string?, amount: number?): boolean
	local changed = false
	for _, list in { data.quests.daily, data.quests.weekly } do
		for _, state in list do
			local def = Progression.questDef(state.id)
			if
				def
				and def.kind == kind
				and (kind ~= "title" or def.titleId == titleId)
				and state.progress < def.target
			then
				state.progress = math.min(def.target, state.progress + (amount or 1))
				changed = true
			end
		end
	end
	return changed
end

-- Coins and XP for finishing a match against the bot.
function Progression.matchReward(level: string, won: boolean): (number, number)
	local rewards = Economy.MatchRewards[level] or Economy.MatchRewards.Easy
	return if won then rewards.win else rewards.loss, if won then Economy.Xp.Win else Economy.Xp.Loss
end

-- Elo update for a ranked match. scoreA: 1 if A won, 0 if A lost. Returns the new ratings.
function Progression.elo(ratingA: number, ratingB: number, scoreA: number, k: number): (number, number)
	local expectedA = 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
	local delta = math.round(k * (scoreA - expectedA))
	return ratingA + delta, ratingB - delta
end

function Progression.cue(id: string): Cues.Cue
	for _, cue in Cues.List do
		if cue.id == id then
			return cue
		end
	end
	return Cues.List[1]
end

return Progression
