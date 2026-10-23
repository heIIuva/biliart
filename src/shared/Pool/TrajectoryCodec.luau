--!strict
-- Packs a simulation's frames and events into a buffer for the network, and unpacks it on the client.
--
-- Layout (little-endian):
--   header: u8 version, u8 recordHz, u16 frameCount, u16 eventCount
--   frame:  u8 ballCount, then per ball: u8 id, i16 x, y, z (0.1 mm), i16 qx, qy, qz (qw >= 0 implied)
--   event:  u8 kind, f32 t, u8 a, u8 b, u16 speed (mm/s)
-- Frame k is at t = k / recordHz.

local PoolPhysics = require("./PoolPhysics")

local VERSION = 1
local HEADER_BYTES = 6
local BALL_BYTES = 13
local EVENT_BYTES = 9
local POSITION_SCALE = 10000 -- units per meter (0.1 mm)
local QUAT_SCALE = 32767
local STRIDE = PoolPhysics.FRAME_STRIDE

export type Decoded = {
	recordHz: number,
	frames: { PoolPhysics.Frame },
	events: { PoolPhysics.Event },
}

local function toI16(value: number, scale: number): number
	return math.clamp(math.round(value * scale), -32767, 32767)
end

local TrajectoryCodec = {}

function TrajectoryCodec.encode(result: PoolPhysics.SimResult): buffer
	local frames, events = result.frames, result.events
	assert(#frames <= 65535 and #events <= 65535, "trajectory too long")

	local size = HEADER_BYTES + #events * EVENT_BYTES
	for _, frame in frames do
		size += 1 + (#frame.data // STRIDE) * BALL_BYTES
	end

	local b = buffer.create(size)
	buffer.writeu8(b, 0, VERSION)
	buffer.writeu8(b, 1, result.recordHz)
	buffer.writeu16(b, 2, #frames)
	buffer.writeu16(b, 4, #events)
	local offset = HEADER_BYTES

	for _, frame in frames do
		local data = frame.data
		buffer.writeu8(b, offset, #data // STRIDE)
		offset += 1
		for i = 1, #data, STRIDE do
			local qx, qy, qz, qw = data[i + 4], data[i + 5], data[i + 6], data[i + 7]
			if qw < 0 then
				qx, qy, qz = -qx, -qy, -qz
			end
			buffer.writeu8(b, offset, data[i])
			buffer.writei16(b, offset + 1, toI16(data[i + 1], POSITION_SCALE))
			buffer.writei16(b, offset + 3, toI16(data[i + 2], POSITION_SCALE))
			buffer.writei16(b, offset + 5, toI16(data[i + 3], POSITION_SCALE))
			buffer.writei16(b, offset + 7, toI16(qx, QUAT_SCALE))
			buffer.writei16(b, offset + 9, toI16(qy, QUAT_SCALE))
			buffer.writei16(b, offset + 11, toI16(qz, QUAT_SCALE))
			offset += BALL_BYTES
		end
	end

	for _, event in events do
		buffer.writeu8(b, offset, event.kind)
		buffer.writef32(b, offset + 1, event.t)
		buffer.writeu8(b, offset + 5, event.a)
		buffer.writeu8(b, offset + 6, event.b)
		buffer.writeu16(b, offset + 7, math.clamp(math.round(event.speed * 1000), 0, 65535))
		offset += EVENT_BYTES
	end
	return b
end

function TrajectoryCodec.decode(b: buffer): Decoded
	assert(buffer.readu8(b, 0) == VERSION, "unknown trajectory version")
	local recordHz = buffer.readu8(b, 1)
	local frameCount = buffer.readu16(b, 2)
	local eventCount = buffer.readu16(b, 4)
	local offset = HEADER_BYTES

	local frames: { PoolPhysics.Frame } = table.create(frameCount)
	for k = 0, frameCount - 1 do
		local count = buffer.readu8(b, offset)
		offset += 1
		local data = table.create(count * STRIDE)
		for i = 0, count - 1 do
			local base = i * STRIDE
			local qx = buffer.readi16(b, offset + 7) / QUAT_SCALE
			local qy = buffer.readi16(b, offset + 9) / QUAT_SCALE
			local qz = buffer.readi16(b, offset + 11) / QUAT_SCALE
			data[base + 1] = buffer.readu8(b, offset)
			data[base + 2] = buffer.readi16(b, offset + 1) / POSITION_SCALE
			data[base + 3] = buffer.readi16(b, offset + 3) / POSITION_SCALE
			data[base + 4] = buffer.readi16(b, offset + 5) / POSITION_SCALE
			data[base + 5] = qx
			data[base + 6] = qy
			data[base + 7] = qz
			data[base + 8] = math.sqrt(math.max(0, 1 - qx * qx - qy * qy - qz * qz))
			offset += BALL_BYTES
		end
		frames[k + 1] = { t = k / recordHz, data = data }
	end

	local events: { PoolPhysics.Event } = table.create(eventCount)
	for i = 1, eventCount do
		events[i] = {
			kind = buffer.readu8(b, offset),
			t = buffer.readf32(b, offset + 1),
			a = buffer.readu8(b, offset + 5),
			b = buffer.readu8(b, offset + 6),
			speed = buffer.readu16(b, offset + 7) / 1000,
		}
		offset += EVENT_BYTES
	end

	return { recordHz = recordHz, frames = frames, events = events }
end

-- One live frame (speed pool): f32 time, u8 count, then per ball the same 13 bytes as above.
function TrajectoryCodec.encodeFrame(t: number, data: { number }): buffer
	local count = #data // STRIDE
	local b = buffer.create(5 + count * BALL_BYTES)
	buffer.writef32(b, 0, t)
	buffer.writeu8(b, 4, count)
	local offset = 5
	for i = 1, #data, STRIDE do
		local qx, qy, qz, qw = data[i + 4], data[i + 5], data[i + 6], data[i + 7]
		if qw < 0 then
			qx, qy, qz = -qx, -qy, -qz
		end
		buffer.writeu8(b, offset, data[i])
		buffer.writei16(b, offset + 1, toI16(data[i + 1], POSITION_SCALE))
		buffer.writei16(b, offset + 3, toI16(data[i + 2], POSITION_SCALE))
		buffer.writei16(b, offset + 5, toI16(data[i + 3], POSITION_SCALE))
		buffer.writei16(b, offset + 7, toI16(qx, QUAT_SCALE))
		buffer.writei16(b, offset + 9, toI16(qy, QUAT_SCALE))
		buffer.writei16(b, offset + 11, toI16(qz, QUAT_SCALE))
		offset += BALL_BYTES
	end
	return b
end

function TrajectoryCodec.decodeFrame(b: buffer): PoolPhysics.Frame
	local count = buffer.readu8(b, 4)
	local data = table.create(count * STRIDE)
	local offset = 5
	for i = 0, count - 1 do
		local base = i * STRIDE
		local qx = buffer.readi16(b, offset + 7) / QUAT_SCALE
		local qy = buffer.readi16(b, offset + 9) / QUAT_SCALE
		local qz = buffer.readi16(b, offset + 11) / QUAT_SCALE
		data[base + 1] = buffer.readu8(b, offset)
		data[base + 2] = buffer.readi16(b, offset + 1) / POSITION_SCALE
		data[base + 3] = buffer.readi16(b, offset + 3) / POSITION_SCALE
		data[base + 4] = buffer.readi16(b, offset + 5) / POSITION_SCALE
		data[base + 5] = qx
		data[base + 6] = qy
		data[base + 7] = qz
		data[base + 8] = math.sqrt(math.max(0, 1 - qx * qx - qy * qy - qz * qz))
		offset += BALL_BYTES
	end
	return { t = buffer.readf32(b, 0), data = data }
end

return TrajectoryCodec
