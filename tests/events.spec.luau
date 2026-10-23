--!strict
local Events = require("../src/shared/Config/Events")
local EventSchedule = require("../src/shared/Game/Events")

-- 2026-10-24 is a Saturday.
local SATURDAY_MIDNIGHT = 1792800000 - (1792800000 % 86400)

return {
	["mini events: 5 minutes out of every 30, rotating, same on every server"] = function()
		local base = 1800 * 1000 -- a slot boundary
		local first = EventSchedule.mini(base)
		assert(first and first.endsAt == base + Events.MiniLength, "running at the start of a slot")
		assert(EventSchedule.mini(base + Events.MiniLength - 1) ~= nil, "still running")
		assert(EventSchedule.mini(base + Events.MiniLength) == nil, "over after 5 minutes")
		local nextAt, nextId = EventSchedule.nextMini(base + 600)
		assert(nextAt == base + 1800, "next slot")
		local second = EventSchedule.mini(nextAt) :: EventSchedule.Mini
		assert(second.id == nextId and second.id ~= first.id, "rotates")
	end,

	["weekly event: Saturday 15:00 UTC for two hours"] = function()
		local saturday = os.date("!*t", SATURDAY_MIDNIGHT) :: { wday: number }
		assert(saturday.wday == 7, "the fixture is a Saturday")
		local start = SATURDAY_MIDNIGHT + 15 * 3600
		assert(EventSchedule.weeklyStart(SATURDAY_MIDNIGHT) == start, "this week's start")
		assert(EventSchedule.weeklyActive(start + 60) and not EventSchedule.weeklyActive(start - 60), "window")
		assert(not EventSchedule.weeklyActive(start + Events.WeeklyLength), "ends after two hours")
		assert(EventSchedule.weeklyStart(start + Events.WeeklyLength + 1) == start + 7 * 86400, "next week")
	end,

	["holidays by UTC date"] = function()
		local function at(month: number, day: number): number
			return os.time({ year = 2027, month = month, day = day, hour = 12 }) :: number
		end
		local h = EventSchedule.holiday(at(2, 1))
		assert(h and h.id == "LunarNewYear", "lunar new year")
		assert(EventSchedule.holiday(at(7, 15)) == nil, "no holiday in July")
	end,
}
