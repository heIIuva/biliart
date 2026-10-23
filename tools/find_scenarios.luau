-- Finds a shot for every title scenario and prints them as a Luau table for TitleScenarios.SHOTS.
-- Run: lune run tools/find_scenarios [titleId...]
local process = require("@lune/process")
local TitleScenarios = require("../src/shared/Pool/TitleScenarios")

local wanted = {}
for _, id in process.args do
	wanted[id] = true
end

local ids = {}
for id in TitleScenarios.all() do
	table.insert(ids, id)
end
table.sort(ids)

for _, id in ids do
	if next(wanted) and not wanted[id] then
		continue
	end
	local scenario = TitleScenarios.all()[id]
	local start = os.clock()
	local shot = TitleScenarios.find(id, scenario)
	local seconds = os.clock() - start
	if shot then
		print(
			string.format(
				"\t%s = { angle = %.17g, power = %.17g, spinX = %.17g, spinY = %.17g, elevation = %.17g }, -- %.1fs",
				id,
				shot.angle,
				shot.power,
				shot.spinX,
				shot.spinY,
				shot.elevation,
				seconds
			)
		)
	else
		print(string.format("\t-- %s: NOT FOUND (%.1fs)", id, seconds))
	end
end
