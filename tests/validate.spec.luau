--!strict
local Physics = require("../src/shared/Config/Physics")
local Validate = require("../src/shared/Util/Validate")

local function shot(overrides: { [string]: any }): { [string]: any }
	local base: { [string]: any } = { angle = 1, power = 0.5, spinX = 0.1, spinY = -0.2, elevation = 0.1 }
	for k, v in overrides do
		base[k] = v
	end
	return base
end

return {
	["accepts a valid shot and returns a clean copy"] = function()
		local input = shot({ extra = "ignored" })
		local result = Validate.shotParams(input)
		assert(result, "valid shot rejected")
		assert(result.power == 0.5 and result.spinY == -0.2, "values changed")
		assert((result :: any).extra == nil, "unknown fields must not pass through")
	end,

	["rejects non-tables and missing fields"] = function()
		for _, value in { nil, 1, "shot", true } :: { any } do
			assert(Validate.shotParams(value) == nil, `accepted {value}`)
		end
		assert(Validate.shotParams(shot({ power = "1" })) == nil, "string power")
		local missing = shot({})
		missing.angle = nil
		assert(Validate.shotParams(missing) == nil, "missing angle")
	end,

	["rejects NaN and infinities"] = function()
		for _, bad in { 0 / 0, math.huge, -math.huge } do
			for _, field in { "angle", "power", "spinX", "spinY", "elevation" } do
				assert(Validate.shotParams(shot({ [field] = bad })) == nil, `{field} = {bad} accepted`)
			end
		end
	end,

	["rejects out-of-range values"] = function()
		assert(Validate.shotParams(shot({ power = 1.01 })) == nil, "power > 1")
		assert(Validate.shotParams(shot({ power = -0.01 })) == nil, "power < 0")
		assert(Validate.shotParams(shot({ spinX = Physics.MaxTipOffset, spinY = 0.1 })) == nil, "spin outside circle")
		assert(Validate.shotParams(shot({ elevation = Physics.MaxElevation + 0.01 })) == nil, "elevation too high")
		assert(Validate.shotParams(shot({ elevation = -0.01 })) == nil, "negative elevation")
		assert(Validate.shotParams(shot({ angle = 1e9 })) == nil, "absurd angle")
		assert(Validate.shotParams(shot({ power = 1, spinX = 0, spinY = Physics.MaxTipOffset })), "edges are valid")
	end,
}
