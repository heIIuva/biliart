-- Finds a solution for every trick of the week; paste into Config/Tricks (solution = ...).
-- Run: lune run tools/find_tricks
local TrickConfig = require("../src/shared/Config/Tricks")
local Tricks = require("../src/shared/Pool/Tricks")

for _, trick in TrickConfig.List do
	local start = os.clock()
	local shot = Tricks.findSolution(trick)
	if shot then
		print(
			string.format(
				"%s: solution = { angle = %.17g, power = %.17g, spinX = 0, spinY = 0, elevation = %.17g }, -- %.1fs",
				trick.id,
				shot.angle,
				shot.power,
				shot.elevation,
				os.clock() - start
			)
		)
	else
		print(string.format("%s: NOT FOUND (%.1fs)", trick.id, os.clock() - start))
	end
end
