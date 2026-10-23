--!strict
-- Allocation-free 2D vector helpers on plain numbers. Pure Luau: no Roblox types.

local Vec = {}

function Vec.dot(ax: number, ay: number, bx: number, by: number): number
	return ax * bx + ay * by
end

function Vec.cross(ax: number, ay: number, bx: number, by: number): number
	return ax * by - ay * bx
end

function Vec.length(x: number, y: number): number
	return math.sqrt(x * x + y * y)
end

function Vec.normalize(x: number, y: number): (number, number)
	local length = math.sqrt(x * x + y * y)
	if length == 0 then
		return 0, 0
	end
	return x / length, y / length
end

return Vec
