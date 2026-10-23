--!strict
local PoolPhysics = require("../src/shared/Pool/PoolPhysics")
local Rack = require("../src/shared/Pool/Rack")
local TableGeometry = require("../src/shared/Pool/TableGeometry")
local TrajectoryCodec = require("../src/shared/Pool/TrajectoryCodec")

local STRIDE = PoolPhysics.FRAME_STRIDE
local POSITION_TOLERANCE = 0.5e-4 + 1e-9 -- half of the 0.1 mm quantum
local QUAT_TOLERANCE = 1e-3

local geo = TableGeometry.get("Standard")

local function simulateBreak(): PoolPhysics.SimResult
	return PoolPhysics.simulateShot(
		{ geometry = geo, balls = Rack.eightBall(geo, 3) },
		{ angle = 0, power = 1, spinX = 0.2, spinY = -0.3, elevation = 0 }
	)
end

return {
	["encode -> decode keeps frames and events within quantization"] = function()
		local result = simulateBreak()
		local packed = TrajectoryCodec.encode(result)
		local decoded = TrajectoryCodec.decode(packed)

		assert(decoded.recordHz == result.recordHz, "recordHz")
		assert(#decoded.frames == #result.frames, `frame count {#decoded.frames} vs {#result.frames}`)
		for k, frame in result.frames do
			local got = decoded.frames[k]
			assert(math.abs(got.t - frame.t) < 1e-9, `frame {k} time`)
			assert(#got.data == #frame.data, `frame {k} ball count`)
			for i = 1, #frame.data, STRIDE do
				assert(got.data[i] == frame.data[i], `frame {k} id`)
				for j = 1, 3 do
					local err = math.abs(got.data[i + j] - frame.data[i + j])
					assert(err <= POSITION_TOLERANCE, `frame {k} ball {frame.data[i]} coord {j} off by {err}`)
				end
				-- q and -q are the same rotation: compare up to sign.
				local dot = 0
				for j = 4, 7 do
					dot += got.data[i + j] * frame.data[i + j]
				end
				assert(1 - math.abs(dot) < QUAT_TOLERANCE, `frame {k} ball {frame.data[i]} rotation off`)
			end
		end

		assert(#decoded.events == #result.events, "event count")
		for i, e in result.events do
			local got = decoded.events[i]
			assert(got.kind == e.kind and got.a == e.a and got.b == e.b, `event {i} fields`)
			assert(math.abs(got.t - e.t) < 1e-5, `event {i} time`)
			assert(math.abs(got.speed - e.speed) <= 0.0005 + 1e-9, `event {i} speed`)
		end
		print(
			string.format(
				"  break trajectory: %d bytes (%d frames, %d events)",
				buffer.len(packed),
				#result.frames,
				#result.events
			)
		)
	end,
}
