--!strict
local RateLimiter = require("../src/shared/Util/RateLimiter")

local function fakeClock()
	local t = 0
	return function()
		return t
	end, function(dt: number)
		t += dt
	end
end

return {
	["burst then refill"] = function()
		local clock, advance = fakeClock()
		local limiter = RateLimiter.new(2, 3, clock)
		assert(limiter:Allow("p"), "should be allowed")
		assert(limiter:Allow("p"), "should be allowed")
		assert(limiter:Allow("p"), "should be allowed")
		assert(not limiter:Allow("p"), "burst exhausted")
		advance(0.5) -- +1 token
		assert(limiter:Allow("p"), "should be allowed")
		assert(not limiter:Allow("p"), "should be limited")
		advance(100) -- capped at burst
		for _ = 1, 3 do
			assert(limiter:Allow("p"), "should be allowed")
		end
		assert(not limiter:Allow("p"), "should be limited")
	end,
	["keys are independent"] = function()
		local clock = fakeClock()
		local limiter = RateLimiter.new(1, 1, clock)
		assert(limiter:Allow("a"), "should be allowed")
		assert(not limiter:Allow("a"), "should be limited")
		assert(limiter:Allow("b"), "should be allowed")
		limiter:Forget("a")
		assert(limiter:Allow("a"), "should be allowed")
	end,
}
