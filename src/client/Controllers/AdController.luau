--!strict
-- Rewarded ads on the client (GDD 14): availability is checked when a panel with an ad button
-- opens (not in advance); the button is shown only if an ad is available, and its text names the
-- reward. Pressing it asks the server, which plays the ad; the reward arrives as a receipt.

local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ads = require(Shared.Config.Ads)
local Remotes = require(Shared.Net.Remotes)

local AdController = {}

-- Calls `show` if a rewarded video can play right now; `button` registers the ad opportunity.
function AdController.whenAvailable(placement: string, button: GuiObject?, show: () -> ())
	task.spawn(function()
		local ok, available = pcall(function()
			local result = AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
			-- TODO(verify-api): the result table's field name; the type definitions only say { [string]: any }.
			return result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
		end)
		if ok and available then
			if button then
				local config = Ads.Placements[placement]
				pcall(function()
					AdService:RegisterAdOpportunityAsync(
						button,
						if config and config.placementId ~= 0 then config.placementId else nil
					)
				end)
			end
			show()
		end
	end)
end

function AdController.request(placement: string)
	Remotes.Event("RequestAd"):FireServer(placement)
end

return AdController
