--!strict
local PoolPhysics = require("../src/shared/Pool/PoolPhysics")
local PoolRules = require("../src/shared/Pool/PoolRules")
local Rack = require("../src/shared/Pool/Rack")
local Rules = require("../src/shared/Config/Rules")
local ShotClassifier = require("../src/shared/Pool/ShotClassifier")
local ShotReport = require("../src/shared/Pool/ShotReport")
local TableGeometry = require("../src/shared/Pool/TableGeometry")
local TitleScenarios = require("../src/shared/Pool/TitleScenarios")
local Titles = require("../src/shared/Config/Titles")
local Tutorial = require("../src/shared/Config/Tutorial")

local geo = TableGeometry.get("Standard")

return {
	["every title has a scenario whose stored shot earns it"] = function()
		local scenarios = TitleScenarios.all()
		for _, title in Titles do
			local scenario = scenarios[title.id]
			assert(scenario, `no scenario for {title.id}`)
			local shot = scenario.shot
			assert(shot, `no stored shot for {title.id}`)
			local result = TitleScenarios.play(scenario, shot)
			assert(result.titleId == title.id, `{title.id}: got {result.titleId} ({result.outcome.reasonKey})`)
		end
	end,

	["report flags behind the special titles"] = function()
		local scenarios = TitleScenarios.all()
		local crane = TitleScenarios.play(scenarios.CRANE, scenarios.CRANE.shot :: PoolPhysics.ShotParams).report
		assert(crane.cueAirborne and crane.jumpedOverBall, "crane: jumped over a ball")
		local serpent = TitleScenarios.play(scenarios.SERPENT, scenarios.SERPENT.shot :: PoolPhysics.ShotParams).report
		assert(serpent.curved, "serpent: curved path")
		local carp = TitleScenarios.play(scenarios.CARP, scenarios.CARP.shot :: PoolPhysics.ShotParams).report
		assert(carp.potDistance >= 1.5, `carp: pot distance {carp.potDistance}`)
		local dragon = TitleScenarios.play(scenarios.DRAGON, scenarios.DRAGON.shot :: PoolPhysics.ShotParams).report
		assert(dragon.cushionsBeforePot >= 2, "dragon: two cushions before the pot")
	end,

	["classifier: the highest priority match wins, titles need a clean shot"] = function()
		local scenarios = TitleScenarios.all()
		local doom = TitleScenarios.play(scenarios.EIGHT_DOOM, scenarios.EIGHT_DOOM.shot :: PoolPhysics.ShotParams)
		assert(doom.report.lostByEight, "the 8 went in early")
		local tiger = ShotClassifier.byId("TIGER") :: Titles.Title
		local report = table.clone(doom.report)
		report.isBreak, report.potted, report.power, report.foul = true, 1, 1, ""
		assert(ShotClassifier.matches(tiger, report), "tiger conditions hold")
		report.foul = "CueScratch"
		assert(not ShotClassifier.matches(tiger, report), "a foul blocks titles")
		local disabled = ShotClassifier.classify(doom.report, { EIGHT_DOOM = true })
		assert(disabled == nil or disabled.id ~= "EIGHT_DOOM", "live config can disable a title")
	end,

	["tutorial break always earns TIGER"] = function()
		local balls = Rack.eightBall(geo, Tutorial.RackSeed)
		for _, b in balls do
			if b.id == 0 then
				b.x, b.y = Tutorial.CueX, Tutorial.CueY
			end
		end
		local rules: PoolRules.RulesState = { current = 1, groups = {}, isBreak = true }
		local sim = PoolPhysics.simulateShot({ geometry = geo, balls = balls }, Tutorial.BreakShot)
		local outcome = PoolRules.evaluate(rules, Rules.Variants.Standard, sim, {})
		local report = ShotReport.build({
			sim = sim,
			shot = Tutorial.BreakShot,
			before = rules,
			outcome = outcome,
			ballsBefore = balls,
			geometry = geo,
			visitOwnPots = 0,
			turnStreak = 1,
		})
		local title = ShotClassifier.classify(report)
		assert(title and title.id == "TIGER", `tutorial break gave {title and title.id}`)
		assert(Tutorial.CueX == geo.headSpotX, "cue on the head spot")
	end,
}
