--!strict
-- Maps simulation coordinates (meters; X along the table, Y across, Z up) to Roblox world space.
-- `surface` is a CFrame at the center of the cloth surface:
--   sim +X -> surface.XVector, sim +Y -> -surface.ZVector, sim +Z -> surface.YVector.
-- The mapping keeps handedness, so quaternions map the same way as vectors.

local Physics = require("../Config/Physics")

local S = Physics.StudsPerMeter

local TableSpace = {}

function TableSpace.studs(meters: number): number
	return meters * S
end

function TableSpace.toWorld(surface: CFrame, x: number, y: number, z: number): Vector3
	return surface:PointToWorldSpace(Vector3.new(x * S, z * S, -y * S))
end

function TableSpace.toTable(surface: CFrame, world: Vector3): (number, number)
	local p = surface:PointToObjectSpace(world)
	return p.X / S, -p.Z / S
end

function TableSpace.direction(surface: CFrame, dx: number, dy: number): Vector3
	return surface:VectorToWorldSpace(Vector3.new(dx, 0, -dy))
end

function TableSpace.ballCFrame(
	surface: CFrame,
	x: number,
	y: number,
	z: number,
	qx: number,
	qy: number,
	qz: number,
	qw: number
): CFrame
	return surface * CFrame.new(x * S, z * S, -y * S, qx, qz, -qy, qw)
end

return TableSpace
