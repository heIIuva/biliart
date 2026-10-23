--!strict
-- Settings panel (GDD 18): music / sfx / announcer volume and graphics quality. Saved on the server.
-- Quality Low (or Auto with a low Roblox graphics level) turns off camera shake.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Net.Remotes)
local Text = require(Shared.Util.Text)
local Kit = require(script.Parent.Parent.UI.Kit)
local Sfx = require(script.Parent.Parent.Util.Sfx)
local MenuController = require(script.Parent.MenuController)
local PlayerDataController = require(script.Parent.PlayerDataController)

local STEP = 0.1
local QUALITIES = { "Auto", "Low", "High" }
local AUTO_LOW_LEVEL = 3 -- Roblox graphics level 1..3 counts as low-end

local settings = { music = 0.6, sfx = 1, announcer = 1, quality = "Auto" }
local labels: { [string]: TextLabel } = {}

local SettingsController = {}

function SettingsController.lowQuality(): boolean
	if settings.quality == "Auto" then
		local level = UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
		return level > 0 and level <= AUTO_LOW_LEVEL -- 0 = Automatic
	end
	return settings.quality == "Low"
end

local function refresh()
	Sfx.setVolumes(settings.music, settings.sfx, settings.announcer)
	for key, label in labels do
		local value = (settings :: any)[key]
		label.Text = if key == "quality"
			then `{Text.get("SETTINGS_QUALITY")}: {Text.get("QUALITY_" .. string.upper(value))}`
			else `{Text.get("SETTINGS_" .. string.upper(key))}: {math.round(value * 100)}%`
	end
end

local function send(change: { [string]: any })
	for k, v in change do
		(settings :: any)[k] = v
	end
	refresh()
	Remotes.Event("SetSettings"):FireServer(change)
end

function SettingsController.Start()
	local gui = Kit.screen("Settings", 6)
	local panel = Kit.frame("Panel", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(380, 290),
		Visible = false,
		Active = true,
	})
	Kit.corner(panel, 0.06)
	for i, key in { "music", "sfx", "announcer", "quality" } do
		local y = 14 + (i - 1) * 58
		labels[key] = Kit.label(key, panel, "", {
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.fromOffset(240, 46),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		if key == "quality" then
			Kit.button("Next", panel, "SETTINGS_CHANGE", {
				Position = UDim2.fromOffset(260, y),
				Size = UDim2.fromOffset(106, 46),
			}, function()
				local index = table.find(QUALITIES, settings.quality) or 1
				send({ quality = QUALITIES[index % #QUALITIES + 1] })
			end)
		else
			for j, delta in { -STEP, STEP } do
				Kit.button(
					if delta < 0 then "Down" else "Up",
					panel,
					if delta < 0 then "SETTINGS_LESS" else "SETTINGS_MORE",
					{
						Position = UDim2.fromOffset(260 + (j - 1) * 56, y),
						Size = UDim2.fromOffset(50, 46),
					},
					function()
						local value = math.clamp((settings :: any)[key] + delta, 0, 1)
						send({ [key] = math.round(value * 10) / 10 })
					end
				)
			end
		end
	end
	Kit.button("Close", panel, "MENU_CLOSE", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.fromOffset(140, 40),
		BackgroundColor3 = Kit.GREY,
	}, function()
		panel.Visible = false
	end)
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	MenuController.addButton("MENU_SETTINGS", 21, function()
		panel.Visible = true
	end, panel)
	PlayerDataController.Changed:Connect(function(data)
		settings = table.clone(data.settings)
		refresh()
	end)
	refresh()
end

return SettingsController
