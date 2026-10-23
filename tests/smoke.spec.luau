--!strict
local Game = require("../src/shared/Config/Game")

return {
	["game config loads"] = function()
		assert(type(Game.Name) == "string" and #Game.Name > 0, "Game.Name must be a non-empty string")
	end,
}
