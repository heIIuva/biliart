--!strict
-- A reproducible setup for every title and anti-title: ball layout, rules context and a shot
-- that earns it. Shots were found offline by tools/find_scenarios.luau (search over the given
-- space) and are checked by tests/hype.spec.luau. Used by the Studio debug command.
-- Pure Luau: no Roblox API.

local PoolPhysics = require("./PoolPhysics")
local PoolRules = require("./PoolRules")
local Rack = require("./Rack")
local Rules = require("../Config/Rules")
local ShotClassifier = require("./ShotClassifier")
local ShotReport = require("./ShotReport")
local TableGeometry = require("./TableGeometry")

export type Search = {
	toward: { x: number, y: number }, -- center of the angle sweep: direction from the cue ball to this point
	spreadDegrees: number,
	stepDegrees: number,
	powers: { number },
	spinsX: { number },
	spinsY: { number },
	elevations: { number }, -- degrees
	calledPocket: number?,
}

export type Scenario = {
	balls: { PoolPhysics.BallState },
	rules: PoolRules.RulesState,
	visitOwnPots: number,
	search: Search,
	shot: PoolPhysics.ShotParams?, -- found shot
	calledPocket: number?,
}

export type Outcome = {
	sim: PoolPhysics.SimResult,
	outcome: PoolRules.RulesResult,
	report: ShotReport.Report,
	titleId: string?,
}

local geo = TableGeometry.get("Standard")
local HL, HW = geo.halfLength, geo.halfWidth
local SOLIDS: { [number]: PoolRules.Group } = { [1] = "Solids", [2] = "Stripes" }

local function layout(list: { { number } }, gone: { number }?): { PoolPhysics.BallState }
	local balls: { PoolPhysics.BallState } = {}
	for _, b in list do
		table.insert(balls, { id = b[1], x = b[2], y = b[3], status = "Stationary" })
	end
	for _, id in (gone or {}) :: { number } do
		table.insert(balls, { id = id, x = 0, y = 0, status = "Pocketed" })
	end
	return balls
end

local function search(toward: { number }, spread: number, step: number, overrides: { [string]: any }?): Search
	local s: Search = {
		toward = { x = toward[1], y = toward[2] },
		spreadDegrees = spread,
		stepDegrees = step,
		powers = { 0.25, 0.4, 0.55, 0.7, 0.85, 1 },
		spinsX = { 0 },
		spinsY = { 0 },
		elevations = { 0 },
	}
	for k, v in (overrides or {}) :: { [string]: any } do
		(s :: any)[k] = v
	end
	return s
end

-- Found by tools/find_scenarios.luau; keyed by title id.
local SHOTS: { [string]: PoolPhysics.ShotParams } = {
	CARP = { angle = 0.2938252863647331, power = 0.25, spinX = 0, spinY = 0, elevation = 0 },
	CRANE = {
		angle = 0.25367409613864272,
		power = 0.59999999999999998,
		spinX = 0,
		spinY = 0,
		elevation = 0.69813170079773179,
	},
	CRICKET = { angle = -0.55859931534356255, power = 0.14999999999999999, spinX = 0, spinY = 0, elevation = 0 },
	DRAGON = { angle = 0.58800260354756761, power = 0.65000000000000002, spinX = 0, spinY = 0, elevation = 0 },
	EIGHT_DOOM = { angle = 0.66242629383315121, power = 0.29999999999999999, spinX = 0, spinY = 0, elevation = 0 },
	FLYAWAY = {
		angle = 1.5707963267948966,
		power = 0.80000000000000004,
		spinX = 0,
		spinY = 0,
		elevation = 0.87266462599716477,
	},
	HEAVEN = { angle = 0.27534752791388417, power = 0.5, spinX = 0, spinY = 0, elevation = 0 },
	MONKEY = { angle = 0.12217304763960307, power = 0.80000000000000004, spinX = 0, spinY = 0, elevation = 0 },
	PANDA = { angle = -0.6347744625333126, power = 0.080000000000000002, spinX = 0, spinY = 0, elevation = 0 },
	PHOENIX = { angle = 0.66068096458115688, power = 0.45000000000000001, spinX = 0, spinY = 0, elevation = 0 },
	RATTLE = { angle = 0.53343818326260684, power = 0.12, spinX = 0, spinY = 0, elevation = 0 },
	SERPENT = {
		angle = 0.53449056379074222,
		power = 0.29999999999999999,
		spinX = 0.5,
		spinY = 0,
		elevation = 0.6108652381980153,
	},
	SHAME = { angle = 0.7695264804056583, power = 0.25, spinX = 0, spinY = 0, elevation = 0 },
	TIGER = { angle = 0, power = 0.90000000000000002, spinX = 0, spinY = 0, elevation = 0 },
	WHIRLWIND = { angle = 0.12217304763960307, power = 0.69999999999999996, spinX = 0, spinY = 0, elevation = 0 },
}

local function build(): { [string]: Scenario }
	return {
		TIGER = {
			balls = Rack.eightBall(geo, 1),
			rules = { current = 1, groups = {}, isBreak = true },
			visitOwnPots = 0,
			search = search({ geo.footSpotX, 0 }, 1.5, 0.25, { powers = { 0.9, 0.95, 1 } }),
		},
		CARP = {
			balls = layout({ { 0, -0.75, -0.55 + 0.1 }, { 1, -0.3, -0.3 }, { 9, -0.9, 0.4 }, { 8, 0.2, -0.45 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ -0.3, -0.3 }, 6, 0.2),
		},
		PANDA = {
			balls = layout({
				{ 0, -0.5, -0.2 },
				{ 1, -0.3, -0.35 },
				{ 9, 1.0, 0.44 },
				{ 3, 0.94, 0.38 },
				{ 4, 0.92, 0.46 },
				{ 5, 1.0, 0.36 },
				{ 8, 0.3, 0.3 },
			}),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ -0.3, -0.35 }, 10, 0.5, { powers = { 0.08, 0.12, 0.16, 0.2 } }),
		},
		DRAGON = {
			balls = layout({ { 0, -0.3, 0 }, { 1, 0, 0.2 }, { 9, 0.6, -0.3 }, { 8, -0.7, 0.35 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 0, 0.2 }, 180, 0.25, { powers = { 0.45, 0.65, 0.85 } }),
		},
		CRANE = {
			balls = layout({ { 0, -0.6, 0.05 }, { 9, -0.47, 0.08 }, { 1, 0.75, 0.4 }, { 8, 0.2, -0.4 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 0.75, 0.4 }, 4, 0.1, { powers = { 0.5, 0.6, 0.7, 0.8 }, elevations = { 40, 48, 55 } }),
		},
		MONKEY = {
			balls = layout({
				{ 0, 0.55, 0 },
				{ 1, 1.0, 0.44 },
				{ 2, 1.0, -0.44 },
				{ 3, 0.8, 0.0 },
				{ 9, -0.6, 0.3 },
				{ 8, -0.4, -0.3 },
			}),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 0.8, 0 }, 25, 0.25, { powers = { 0.6, 0.8, 1 } }),
		},
		WHIRLWIND = {
			balls = layout({
				{ 0, 0.55, 0 },
				{ 1, 1.0, 0.44 },
				{ 2, 1.0, -0.44 },
				{ 3, 0.8, 0.0 },
				{ 4, 0.04, 0.47 },
				{ 5, 0.04, -0.47 },
				{ 9, -0.6, 0.3 },
				{ 8, -0.4, -0.3 },
			}),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 0.8, 0 }, 40, 0.25, { powers = { 0.7, 0.85, 1 } }),
		},
		SERPENT = {
			balls = layout({ { 0, 0.3, 0.05 }, { 1, 1.0, 0.44 }, { 9, -0.6, 0.3 }, { 8, -0.4, -0.3 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 1.0, 0.44 }, 30, 0.5, {
				powers = { 0.2, 0.3, 0.4, 0.5 },
				spinsX = { -0.5, 0.5 },
				elevations = { 35, 45, 55 },
			}),
		},
		PHOENIX = {
			balls = layout({ { 0, 0.5, 0.05 }, { 8, 1.0, 0.44 }, { 9, -0.6, 0.3 } }, { 1, 2, 3, 4, 5, 6, 7 }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 7,
			search = search({ 1.0, 0.44 }, 3, 0.1, { powers = { 0.3, 0.45 }, calledPocket = 6 }),
			calledPocket = 6,
		},
		HEAVEN = {
			balls = layout({ { 0, -0.6, 0.0 }, { 8, 1.0, 0.44 }, { 1, 0.6, -0.2 }, { 9, 0.7, -0.3 } }),
			rules = { current = 1, groups = {}, isBreak = true },
			visitOwnPots = 0,
			search = search({ 1.0, 0.44 }, 3, 0.1, { powers = { 0.5, 0.7 } }),
		},
		SHAME = {
			balls = layout({ { 0, 0.8, 0.25 }, { 1, -0.6, -0.3 }, { 9, -0.6, 0.3 }, { 8, 0, -0.3 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ HL, HW }, 2, 0.1, { powers = { 0.25, 0.35 } }),
		},
		CRICKET = {
			balls = layout({ { 0, 0, -0.3 }, { 1, 0.6, 0.3 }, { 9, -0.6, 0.3 }, { 8, -0.6, -0.3 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 0.4, -0.55 }, 2, 0.5, { powers = { 0.15, 0.2 } }),
		},
		RATTLE = {
			balls = layout({ { 0, 0.6, 0.15 }, { 1, 0.85, 0.3 }, { 9, -0.6, 0.3 }, { 8, -0.4, -0.3 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 0.85, 0.3 }, 12, 0.1, { powers = { 0.12, 0.16, 0.2, 0.25, 0.3 } }),
		},
		EIGHT_DOOM = {
			balls = layout({ { 0, 0.5, 0.05 }, { 8, 1.0, 0.44 }, { 1, -0.6, -0.3 }, { 9, -0.6, 0.3 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 1.0, 0.44 }, 3, 0.1, { powers = { 0.3, 0.45 }, calledPocket = 6 }),
			calledPocket = 6,
		},
		FLYAWAY = {
			balls = layout({ { 0, 0.6, 0.25 }, { 1, -0.6, -0.3 }, { 9, -0.6, 0.3 }, { 8, 0, -0.3 } }),
			rules = { current = 1, groups = SOLIDS, isBreak = false },
			visitOwnPots = 0,
			search = search({ 0.6, HW }, 20, 1, { powers = { 0.8, 0.9, 1 }, elevations = { 50, 55, 60 } }),
		},
	}
end

local TitleScenarios = {}

TitleScenarios.SHOTS = SHOTS

function TitleScenarios.all(): { [string]: Scenario }
	local scenarios = build()
	for id, scenario in scenarios do
		scenario.shot = SHOTS[id]
	end
	return scenarios
end

function TitleScenarios.play(scenario: Scenario, shot: PoolPhysics.ShotParams): Outcome
	local variant = Rules.Variants.Standard
	local sim = PoolPhysics.simulateShot({ geometry = geo, balls = scenario.balls }, shot, { record = false })
	local called = scenario.calledPocket or scenario.search.calledPocket
	local outcome = PoolRules.evaluate(scenario.rules, variant, sim, { calledPocket = called })
	local report = ShotReport.build({
		sim = sim,
		shot = shot,
		before = scenario.rules,
		outcome = outcome,
		ballsBefore = scenario.balls,
		geometry = geo,
		visitOwnPots = scenario.visitOwnPots,
		turnStreak = 1,
	})
	local title = ShotClassifier.classify(report)
	return { sim = sim, outcome = outcome, report = report, titleId = if title then title.id else nil }
end

-- Sweeps the scenario's search space; returns the first shot classified as `titleId`.
function TitleScenarios.find(titleId: string, scenario: Scenario): PoolPhysics.ShotParams?
	local s = scenario.search
	local cue: PoolPhysics.BallState? = nil
	for _, b in scenario.balls do
		if b.id == 0 then
			cue = b
		end
	end
	assert(cue, "scenario without a cue ball")
	local center = math.atan2(s.toward.y - cue.y, s.toward.x - cue.x)
	local steps = math.floor(s.spreadDegrees / s.stepDegrees + 0.5)
	for i = 0, steps do
		for _, sign in { 1, -1 } do
			if i == 0 and sign == -1 then
				continue
			end
			local angle = center + sign * math.rad(i * s.stepDegrees)
			for _, power in s.powers do
				for _, elevation in s.elevations do
					for _, spinX in s.spinsX do
						for _, spinY in s.spinsY do
							local shot = {
								angle = angle,
								power = power,
								spinX = spinX,
								spinY = spinY,
								elevation = math.rad(elevation),
							}
							if TitleScenarios.play(scenario, shot).titleId == titleId then
								return shot
							end
						end
					end
				end
			end
		end
	end
	return nil
end

return TitleScenarios
