--!strict
-- Event schedule as pure functions (tested in Lune).

local Events = require("../Config/Events")

export type Mini = { id: string, endsAt: number }

local EventSchedule = {}

-- The running mini event, or nil.
function EventSchedule.mini(time: number, order: { string }?): Mini?
	local list = order or Events.MiniOrder
	local slot = time // Events.MiniEvery
	local startedAt = slot * Events.MiniEvery
	if time - startedAt >= Events.MiniLength or #list == 0 then
		return nil
	end
	return { id = list[slot % #list + 1], endsAt = startedAt + Events.MiniLength }
end

-- When the next mini event starts (if none is running) and which one.
function EventSchedule.nextMini(time: number, order: { string }?): (number, string)
	local list = order or Events.MiniOrder
	local slot = time // Events.MiniEvery + 1
	return slot * Events.MiniEvery, list[slot % #list + 1]
end

local function weekStart(time: number): number
	local day = time // 86400
	local weekday = (day + 4) % 7 -- 1970-01-01 was a Thursday (4)
	return (day - weekday) * 86400
end

function EventSchedule.weeklyStart(time: number): number
	local start = weekStart(time) + Events.WeeklyDay * 86400 + Events.WeeklyHour * 3600
	if time >= start + Events.WeeklyLength then
		start += 7 * 86400
	end
	return start
end

function EventSchedule.weeklyActive(time: number): boolean
	local start = EventSchedule.weeklyStart(time)
	return time >= start and time < start + Events.WeeklyLength
end

-- The holiday running on this UTC date, or nil.
function EventSchedule.holiday(time: number, holidays: { Events.Holiday }?): Events.Holiday?
	local date = os.date("!*t", time) :: { month: number, day: number }
	local today = string.format("%02d-%02d", date.month, date.day)
	for _, holiday in holidays or Events.Holidays do
		if today >= holiday.from and today <= holiday.to then
			return holiday
		end
	end
	return nil
end

return EventSchedule
