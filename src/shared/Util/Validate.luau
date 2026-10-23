--!strict
-- Validation of untrusted remote payloads. Pure Luau so it is covered by Lune tests.

local Physics = require("../Config/Physics")
local PoolPhysics = require("../Pool/PoolPhysics")

local TOLERANCE = 1e-6

local Validate = {}

-- A finite number, or nil (rejects NaN, ±inf and non-numbers).
function Validate.finite(value: unknown): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

-- Shot intent from a client. Returns a clean copy, or nil if anything is missing or out of range.
function Validate.shotParams(value: unknown): PoolPhysics.ShotParams?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [unknown]: unknown }
	local angle = Validate.finite(raw.angle)
	local power = Validate.finite(raw.power)
	local spinX = Validate.finite(raw.spinX)
	local spinY = Validate.finite(raw.spinY)
	local elevation = Validate.finite(raw.elevation)
	if not (angle and power and spinX and spinY and elevation) then
		return nil
	end
	if math.abs(angle) > 4 * math.pi or power < 0 or power > 1 then
		return nil
	end
	if math.sqrt(spinX * spinX + spinY * spinY) > Physics.MaxTipOffset + TOLERANCE then
		return nil
	end
	if elevation < 0 or elevation > Physics.MaxElevation + TOLERANCE then
		return nil
	end
	return { angle = angle, power = power, spinX = spinX, spinY = spinY, elevation = elevation }
end

return Validate
