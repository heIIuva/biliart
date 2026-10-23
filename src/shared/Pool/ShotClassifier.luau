--!strict
-- Picks the title (or anti-title) for a shot from Config/Titles data. Pure Luau.

local ShotReport = require("./ShotReport")
local Titles = require("../Config/Titles")

-- Named checks for titles whose condition data can't express. Empty for now.
local PREDICATES: { [string]: (ShotReport.Report) -> boolean } = {}

local ShotClassifier = {}

local function fieldOf(key: string, prefix: string): string
	local rest = string.sub(key, #prefix + 1)
	return string.lower(string.sub(rest, 1, 1)) .. string.sub(rest, 2)
end

function ShotClassifier.matches(title: Titles.Title, report: ShotReport.Report): boolean
	local fields = report :: any
	if title.kind == "Title" and report.foul ~= "" then
		return false
	end
	for key, expected in title.conditions do
		if string.sub(key, 1, 3) == "min" then
			local value = fields[fieldOf(key, "min")]
			if type(value) ~= "number" or value < expected then
				return false
			end
		elseif string.sub(key, 1, 3) == "max" then
			local value = fields[fieldOf(key, "max")]
			if type(value) ~= "number" or value > expected then
				return false
			end
		elseif fields[key] ~= expected then
			return false
		end
	end
	if title.predicate then
		local check = PREDICATES[title.predicate]
		return check ~= nil and check(report)
	end
	return true
end

-- The matching title with the highest priority, or nil. `disabled` comes from live config.
function ShotClassifier.classify(report: ShotReport.Report, disabled: { [string]: boolean }?): Titles.Title?
	local best: Titles.Title? = nil
	for _, title in Titles do
		if not (disabled and disabled[title.id]) and ShotClassifier.matches(title, report) then
			if not best or title.priority > best.priority then
				best = title
			end
		end
	end
	return best
end

function ShotClassifier.byId(id: string): Titles.Title?
	for _, title in Titles do
		if title.id == id then
			return title
		end
	end
	return nil
end

return ShotClassifier
