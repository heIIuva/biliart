--!strict
local LiveConfig = require("../src/shared/Game/LiveConfig")

return {
	["live config: a valid document applies every field"] = function()
		local config, errors = LiveConfig.parse({
			disabledTitles = { "CARP" },
			titleNames = { TIGER = { en = "TIGER!!", ru = "ТИГР!!" } },
			codes = { SPRING = { coins = 500 } },
			miniOrder = { "TigerNight", "GoldenHour" },
			holidays = { { id = "Test", nameKey = "HOLIDAY_LANTERNS", from = "03-01", to = "03-02" } },
			flags = { Ads = false },
			news = { en = "New trick!", ru = "Новый трюк!" },
		})
		assert(#errors == 0, table.concat(errors, "; "))
		assert(config.disabledTitles.CARP and config.titleNames.TIGER.ru == "ТИГР!!", "titles")
		assert(config.codes.SPRING.coins == 500, "codes")
		assert(config.miniOrder and config.miniOrder[1] == "TigerNight", "mini order")
		assert(config.holidays and #config.holidays == 1, "holidays")
		assert(not LiveConfig.enabled(config, "Ads") and LiveConfig.enabled(config, "Chaos"), "flags")
		assert(config.news and config.news.en == "New trick!", "news")
	end,

	["live config: bad fields are dropped one by one, the rest still applies"] = function()
		local config, errors = LiveConfig.parse({
			disabledTitles = { "NOT_A_TITLE", "DRAGON" },
			codes = { lower = { coins = 1 }, OK = { coins = 10 }, NEG = { coins = -5 }, HUGE = { gems = 1e9 } },
			miniOrder = { "GoldenHour", "Party" },
			flags = { Ads = "no", Unknown = true },
			news = { en = string.rep("x", 500), ru = "!" },
		})
		assert(config.disabledTitles.DRAGON and not config.disabledTitles.NOT_A_TITLE, "known titles only")
		assert(config.codes.OK and not config.codes.lower and not config.codes.NEG and not config.codes.HUGE, "codes")
		assert(config.miniOrder == nil and config.news == nil, "invalid parts fall back")
		assert(LiveConfig.enabled(config, "Ads"), "a bad flag does not turn the feature off")
		assert(#errors >= 7, `errors reported: {#errors}`)
	end,

	["live config: garbage falls back to defaults"] = function()
		for _, junk in { nil, 42, "text", true } :: { any } do
			local config, errors = LiveConfig.parse(junk)
			assert(#errors == 1 and next(config.disabledTitles) == nil, "defaults")
		end
	end,
}
