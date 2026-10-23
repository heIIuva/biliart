--!strict
-- Token bucket per key (usually a Player): refills `rate` tokens per second up to `burst`.
-- Pure Luau (clock is injectable) so it runs in Lune tests.

type Bucket = { tokens: number, last: number }

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(rate: number, burst: number, clock: (() -> number)?)
	return setmetatable({
		_rate = rate,
		_burst = burst,
		_clock = clock or os.clock,
		_buckets = {} :: { [any]: Bucket },
	}, RateLimiter)
end

export type RateLimiter = typeof(RateLimiter.new(1, 1))

function RateLimiter.Allow(self: RateLimiter, key: any): boolean
	local now = self._clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._burst, last = now }
		self._buckets[key] = bucket
	end
	bucket.tokens = math.min(self._burst, bucket.tokens + (now - bucket.last) * self._rate)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Call on PlayerRemoving so buckets don't leak.
function RateLimiter.Forget(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter
