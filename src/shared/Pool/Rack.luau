--!strict
-- Ball setups. Pure Luau: no Roblox API.

local Physics = require("../Config/Physics")
local PoolPhysics = require("./PoolPhysics")
local TableGeometry = require("./TableGeometry")

-- Rows from the apex (on the foot spot) towards the foot rail: 8 in the middle,
-- one solid and one stripe in the back corners.
local EIGHT_BALL_ROWS = {
	{ 1 },
	{ 9, 2 },
	{ 10, 8, 3 },
	{ 11, 4, 12, 5 },
	{ 6, 14, 7, 15, 13 },
}

-- Park-Miller minimal standard generator: products stay below 2^53, so results are exact
-- and identical on server, client and in Lune.
local function prng(seed: number): () -> number
	local state = seed % 2147483646 + 1
	return function()
		state = state * 48271 % 2147483647
		return state / 2147483647
	end
end

local Rack = {}

-- 8-ball rack with the cue ball on the head spot. A perfect grid makes every contact in the
-- rack simultaneous, and the sequential solver then sends the energy down one edge; real racks
-- have tiny irregular gaps, so each ball is jittered by up to half the gap (never overlapping).
-- The same seed always gives the same rack.
function Rack.eightBall(geometry: TableGeometry.Geometry, seed: number): { PoolPhysics.BallState }
	local random = prng(seed)
	local spacing = 2 * geometry.ballRadius + Physics.RackGap
	local jitter = Physics.RackGap / 2
	local balls: { PoolPhysics.BallState } = {
		{ id = 0, x = geometry.headSpotX, y = 0, status = "Stationary" },
	}
	for row, ids in EIGHT_BALL_ROWS do
		local x = geometry.footSpotX + (row - 1) * spacing * math.sqrt(3) / 2
		for i, id in ids do
			local y = ((i - 1) - (row - 1) / 2) * spacing
			local angle = random() * 2 * math.pi
			local radius = random() * jitter
			table.insert(balls, {
				id = id,
				x = x + radius * math.cos(angle),
				y = y + radius * math.sin(angle),
				status = "Stationary",
			})
		end
	end
	return balls
end

return Rack
