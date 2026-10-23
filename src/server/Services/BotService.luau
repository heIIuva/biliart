--!strict
-- Runs BotPlanner without blocking the server: planning yields every few milliseconds, and the
-- bot "thinks" for a random 1–3 s (per level) so its turn looks natural.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Bot = require(Shared.Config.Bot)
local BotPlanner = require(Shared.Pool.BotPlanner)

local random = Random.new()

local BotService = {}

-- Plans a shot and calls `onPlan` with it, unless `stillValid` says the turn is gone by then.
function BotService.takeTurn(
	ctx: BotPlanner.Context,
	level: string,
	stillValid: () -> boolean,
	onPlan: (BotPlanner.Plan) -> ()
)
	local started = os.clock()
	local sliceStart = os.clock()
	local plan = BotPlanner.plan(ctx, level, function()
		return random:NextNumber()
	end, function()
		if os.clock() - sliceStart > Bot.YieldEverySeconds then
			task.wait()
			sliceStart = os.clock()
		end
	end)
	local think = Bot.Levels[level].ThinkSeconds
	local remaining = random:NextNumber(think[1], think[2]) - (os.clock() - started)
	if remaining > 0 then
		task.wait(remaining)
	end
	if stillValid() then
		onPlan(plan)
	end
end

return BotService
