--!strict
-- Live config (GDD 17): parsed and validated field by field. A bad field is dropped (and reported),
-- the rest still applies; anything missing falls back to Config. Pure Luau, tested in Lune.

local Events = require("../Config/Events")
local Strings = require("../Config/Strings")
local Titles = require("../Config/Titles")

export type Names = { en: string, ru: string }
export type Reward = { coins: number?, gems: number? }

export type LiveConfig = {
	disabledTitles: { [string]: boolean },
	titleNames: { [string]: Names },
	codes: { [string]: Reward },
	miniOrder: { string }?,
	holidays: { Events.Holiday }?,
	flags: { [string]: boolean },
	news: Names?,
}

local FLAGS = { Ads = true, Chaos = true, Speed = true, Trick = true, Sandbox = true, Ranked = true }
local MINI = { GoldenHour = true, TigerNight = true, LanternRain = true }
local MAX_NAME, MAX_NEWS, MAX_CODE = 40, 160, 24

local LiveConfig = {}

function LiveConfig.default(): LiveConfig
	return { disabledTitles = {}, titleNames = {}, codes = {}, miniOrder = nil, holidays = nil, flags = {}, news = nil }
end

local function knownTitle(id: unknown): boolean
	if type(id) ~= "string" then
		return false
	end
	for _, title in Titles do
		if title.id == id then
			return true
		end
	end
	return false
end

local function names(value: unknown, max: number): Names?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [unknown]: unknown }
	local en, ru = raw.en, raw.ru
	if type(en) == "string" and type(ru) == "string" and #en > 0 and #ru > 0 and #en <= max and #ru <= max * 2 then
		return { en = en, ru = ru }
	end
	return nil
end

local function amount(value: unknown, max: number): number?
	if value == nil then
		return nil
	end
	if type(value) == "number" and value >= 0 and value <= max and value == math.floor(value) then
		return value
	end
	error("bad amount")
end

-- Parses a decoded JSON table. Returns the config and the list of dropped fields.
function LiveConfig.parse(decoded: unknown): (LiveConfig, { string })
	local config = LiveConfig.default()
	local errors = {}
	if type(decoded) ~= "table" then
		return config, { "root is not an object" }
	end
	local raw = decoded :: { [unknown]: unknown }

	if raw.disabledTitles ~= nil then
		if type(raw.disabledTitles) == "table" then
			for _, id in raw.disabledTitles :: { unknown } do
				if knownTitle(id) then
					config.disabledTitles[id :: string] = true
				else
					table.insert(errors, `disabledTitles: unknown title {id}`)
				end
			end
		else
			table.insert(errors, "disabledTitles: not a list")
		end
	end

	if type(raw.titleNames) == "table" then
		for id, value in raw.titleNames :: { [unknown]: unknown } do
			local parsed = names(value, MAX_NAME)
			if knownTitle(id) and parsed then
				config.titleNames[id :: string] = parsed
			else
				table.insert(errors, `titleNames: bad entry {id}`)
			end
		end
	end

	if type(raw.codes) == "table" then
		for code, value in raw.codes :: { [unknown]: unknown } do
			local ok, reward = pcall(function(): Reward
				if type(code) ~= "string" or #code == 0 or #code > MAX_CODE or code ~= string.upper(code) then
					error("bad code")
				end
				if type(value) ~= "table" then
					error("bad reward")
				end
				local r = value :: { [unknown]: unknown }
				return { coins = amount(r.coins, 1000000), gems = amount(r.gems, 10000) }
			end)
			if ok then
				config.codes[code :: string] = reward
			else
				table.insert(errors, `codes: bad entry {code}`)
			end
		end
	end

	if raw.miniOrder ~= nil then
		local list = {}
		local valid = type(raw.miniOrder) == "table"
		if valid then
			for _, id in raw.miniOrder :: { unknown } do
				valid = valid and type(id) == "string" and MINI[id :: string] == true
				table.insert(list, id :: string)
			end
		end
		if valid and #list > 0 then
			config.miniOrder = list
		else
			table.insert(errors, "miniOrder: invalid")
		end
	end

	if raw.holidays ~= nil then
		local list: { Events.Holiday } = {}
		local valid = type(raw.holidays) == "table"
		if valid then
			for _, h in raw.holidays :: { unknown } do
				local entry: { [unknown]: unknown } = if type(h) == "table" then h :: { [unknown]: unknown } else {}
				local id, key, from, to = entry.id, entry.nameKey, entry.from, entry.to
				local okDate = function(d: unknown): boolean
					return type(d) == "string" and string.match(d, "^%d%d%-%d%d$") ~= nil
				end
				if type(id) == "string" and type(key) == "string" and Strings[key] and okDate(from) and okDate(to) then
					table.insert(list, { id = id, nameKey = key, from = from :: string, to = to :: string })
				else
					valid = false
				end
			end
		end
		if valid then
			config.holidays = list
		else
			table.insert(errors, "holidays: invalid")
		end
	end

	if type(raw.flags) == "table" then
		for flag, value in raw.flags :: { [unknown]: unknown } do
			if type(flag) == "string" and FLAGS[flag] and type(value) == "boolean" then
				config.flags[flag] = value
			else
				table.insert(errors, `flags: bad entry {flag}`)
			end
		end
	end

	if raw.news ~= nil then
		local parsed = names(raw.news, MAX_NEWS)
		if parsed then
			config.news = parsed
		else
			table.insert(errors, "news: invalid")
		end
	end

	return config, errors
end

-- Features are on unless live config turns them off.
function LiveConfig.enabled(config: LiveConfig, flag: string): boolean
	return config.flags[flag] ~= false
end

return LiveConfig
