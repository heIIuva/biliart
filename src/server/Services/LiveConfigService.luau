--!strict
-- Live config (GDD 17): JSON in DataStore "LiveConfig", key "current". Read at start, every
-- 5 minutes and instantly on a MessagingService ping. Invalid fields fall back to Config.
-- See docs/LIVE_CONFIG.md for the format and how to change it from the Studio command bar.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local LiveConfig = require(Shared.Game.LiveConfig)
local Remotes = require(Shared.Net.Remotes)
local Signal = require(Shared.Util.Signal)
local SocialService = require(script.Parent.SocialService)

local STORE, KEY, TOPIC = "LiveConfig", "current", "LiveConfigUpdated"
local REFRESH_SECONDS = 300

local current = LiveConfig.default()

local LiveConfigService = {
	Changed = Signal.new(), -- (config)
}

function LiveConfigService.get(): LiveConfig.LiveConfig
	return current
end

function LiveConfigService.enabled(flag: string): boolean
	return LiveConfig.enabled(current, flag)
end

-- What clients need: title name overrides, feature flags, news.
local function clientView(): { [string]: any }
	return { titleNames = current.titleNames, flags = current.flags, news = current.news }
end

local function load()
	local ok, value = pcall(function()
		return DataStoreService:GetDataStore(STORE):GetAsync(KEY)
	end)
	if not ok then
		return -- keep what we have
	end
	local decoded = nil
	if type(value) == "string" then
		local parsed, result = pcall(function()
			return HttpService:JSONDecode(value)
		end)
		decoded = if parsed then result else nil
	elseif type(value) == "table" then
		decoded = value
	end
	local config, errors = if decoded ~= nil then LiveConfig.parse(decoded) else LiveConfig.default(), {}
	for _, message in errors do
		warn(`[LiveConfig] {message}`)
	end
	current = config
	SocialService.setLiveCodes(config.codes)
	Remotes.Event("LiveConfig"):FireAllClients(clientView())
	LiveConfigService.Changed:Fire(config)
end

function LiveConfigService.Start()
	task.spawn(function()
		while true do
			load()
			task.wait(REFRESH_SECONDS)
		end
	end)
	task.spawn(pcall, function()
		MessagingService:SubscribeAsync(TOPIC, function()
			load()
		end)
	end)
	Players.PlayerAdded:Connect(function(player)
		Remotes.Event("LiveConfig"):FireClient(player, clientView())
	end)
end

return LiveConfigService
