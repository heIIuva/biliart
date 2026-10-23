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

-- Pocket id 1..6, or nil.
function Validate.pocket(value: unknown): number?
	local n = Validate.finite(value)
	if n and n == math.floor(n) and n >= 1 and n <= 6 then
		return n
	end
	return nil
end

-- A table point { x, y } with finite coordinates (range is checked against the table by the caller).
function Validate.point(value: unknown): { x: number, y: number }?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [unknown]: unknown }
	local x, y = Validate.finite(raw.x), Validate.finite(raw.y)
	if x and y then
		return { x = x, y = y }
	end
	return nil
end

-- Bot difficulty name, or nil.
function Validate.botLevel(value: unknown): string?
	if value == "Easy" or value == "Medium" or value == "Hard" then
		return value
	end
	return nil
end

export type Settings = { music: number, sfx: number, announcer: number, quality: string }

-- New settings from a client payload: volumes 0..1, quality Auto | Low | High; other fields kept.
function Validate.settings(current: Settings, value: unknown): Settings?
	if type(value) ~= "table" then
		return nil
	end
	local raw = value :: { [unknown]: unknown }
	local result = table.clone(current)
	for _, key in { "music", "sfx", "announcer" } do
		if raw[key] ~= nil then
			local n = Validate.finite(raw[key])
			if not n then
				return nil
			end
			(result :: any)[key] = math.clamp(n, 0, 1)
		end
	end
	if raw.quality ~= nil then
		if raw.quality ~= "Auto" and raw.quality ~= "Low" and raw.quality ~= "High" then
			return nil
		end
		result.quality = raw.quality :: string
	end
	return result
end

return Validate
