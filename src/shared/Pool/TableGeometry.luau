--!strict
-- Table layout in meters. Origin at the table center, X along the long side, Y across, Z up.
-- The playing field is the rectangle between the cushion noses. Pure Luau: no Roblox API.
--
-- Pocket ids:  4 --- 5 --- 6      Rail (cushion) ids:   5 | 4
--              |           |                          6       3
--              1 --- 2 --- 3                            1 | 2
-- Head (break) side is -X, rack (foot) side is +X.

local Physics = require("../Config/Physics")
local Vec = require("./Vec")

export type Variant = "Standard" | "Chinese8"

export type Segment = {
	ax: number,
	ay: number,
	bx: number,
	by: number,
	dx: number, -- unit direction A -> B
	dy: number,
	len: number,
	nx: number, -- unit normal facing the side balls arrive from
	ny: number,
	cushionId: number, -- rails: 1..6, jaw walls: 0
	pocketId: number, -- jaw walls: owning pocket, rails: 0
	pocketA: number, -- pocket whose jaw (knuckle) endpoint A belongs to
	pocketB: number,
}

export type Pocket = {
	id: number,
	x: number, -- capture circle: a ball whose center enters it is pocketed
	y: number,
	radius: number,
}

export type Geometry = {
	variant: Variant,
	halfLength: number,
	halfWidth: number,
	ballRadius: number,
	headSpotX: number,
	footSpotX: number,
	segments: { Segment },
	pockets: { Pocket },
}

local VARIANTS: { [Variant]: { length: number, width: number, cornerMouth: number, sideMouth: number } } = {
	Standard = { length = 2.24, width = 1.12, cornerMouth = 0.12, sideMouth = 0.13 },
	Chinese8 = { length = 2.24, width = 1.12, cornerMouth = 0.095, sideMouth = 0.1 },
}

-- Jaw walls run from the mouth points into the pocket; they must reach past the capture circles.
local CORNER_JAW_LENGTH = 0.1
local SIDE_JAW_LENGTH = 0.07
local CORNER_CAPTURE_RADIUS = 0.035 -- centered on the field corner
local SIDE_CAPTURE_OFFSET = 0.025 -- behind the rail line
local SIDE_CAPTURE_RADIUS = 0.035

local function segment(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	nx: number,
	ny: number,
	cushionId: number,
	pocketId: number,
	pocketA: number,
	pocketB: number
): Segment
	local dx, dy = Vec.normalize(bx - ax, by - ay)
	return {
		ax = ax,
		ay = ay,
		bx = bx,
		by = by,
		dx = dx,
		dy = dy,
		len = Vec.length(bx - ax, by - ay),
		nx = nx,
		ny = ny,
		cushionId = cushionId,
		pocketId = pocketId,
		pocketA = pocketA,
		pocketB = pocketB,
	}
end

local function build(variant: Variant): Geometry
	local spec = VARIANTS[variant]
	assert(spec, `Unknown table variant "{variant}"`)
	local hl, hw = spec.length / 2, spec.width / 2
	local jc = spec.cornerMouth / math.sqrt(2) -- distance from the field corner to a corner jaw point
	local js = spec.sideMouth / 2
	local r = Physics.BallRadius

	local segments = {
		segment(-hl + jc, -hw, -js, -hw, 0, 1, 1, 0, 1, 2),
		segment(js, -hw, hl - jc, -hw, 0, 1, 2, 0, 2, 3),
		segment(hl, -hw + jc, hl, hw - jc, -1, 0, 3, 0, 3, 6),
		segment(hl - jc, hw, js, hw, 0, -1, 4, 0, 6, 5),
		segment(-js, hw, -hl + jc, hw, 0, -1, 5, 0, 5, 4),
		segment(-hl, hw - jc, -hl, -hw + jc, 1, 0, 6, 0, 4, 1),
	}
	local pockets: { Pocket } = {}

	local function corner(id: number, sx: number, sy: number)
		local d = CORNER_JAW_LENGTH / math.sqrt(2)
		local n = 1 / math.sqrt(2)
		local p1x, p1y = sx * (hl - jc), sy * hw -- on the long rail
		local p2x, p2y = sx * hl, sy * (hw - jc) -- on the short rail
		table.insert(segments, segment(p1x, p1y, p1x + sx * d, p1y + sy * d, sx * n, -sy * n, 0, id, id, id))
		table.insert(segments, segment(p2x, p2y, p2x + sx * d, p2y + sy * d, -sx * n, sy * n, 0, id, id, id))
		table.insert(pockets, { id = id, x = sx * hl, y = sy * hw, radius = CORNER_CAPTURE_RADIUS })
	end

	local function side(id: number, sy: number)
		local d = SIDE_JAW_LENGTH
		table.insert(segments, segment(-js, sy * hw, -js, sy * (hw + d), 1, 0, 0, id, id, id))
		table.insert(segments, segment(js, sy * hw, js, sy * (hw + d), -1, 0, 0, id, id, id))
		table.insert(pockets, { id = id, x = 0, y = sy * (hw + SIDE_CAPTURE_OFFSET), radius = SIDE_CAPTURE_RADIUS })
	end

	corner(1, -1, -1)
	side(2, -1)
	corner(3, 1, -1)
	corner(4, -1, 1)
	side(5, 1)
	corner(6, 1, 1)
	table.sort(pockets, function(a, b)
		return a.id < b.id
	end)

	-- Physics skips pocket/cushion checks while a ball stays inside |x| <= hl - r, |y| <= hw - r.
	for _, pocket in pockets do
		local cx = math.clamp(pocket.x, -(hl - r), hl - r)
		local cy = math.clamp(pocket.y, -(hw - r), hw - r)
		assert(Vec.length(pocket.x - cx, pocket.y - cy) > pocket.radius, "capture circle intrudes into the field")
	end

	return {
		variant = variant,
		halfLength = hl,
		halfWidth = hw,
		ballRadius = r,
		headSpotX = -hl / 2,
		footSpotX = hl / 2,
		segments = segments,
		pockets = pockets,
	}
end

local cache: { [Variant]: Geometry } = {}

local TableGeometry = {}

function TableGeometry.get(variant: Variant): Geometry
	local geometry = cache[variant]
	if not geometry then
		geometry = build(variant)
		cache[variant] = geometry
	end
	return geometry
end

return TableGeometry
