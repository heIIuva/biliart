--!strict
-- Daily and weekly quest pools (GDD 10.5). Kinds: "title" (earn titleId), "wins", "pots",
-- "spinPots" (pots with |spin| >= 0.2), "matches". Three of each are picked per player per day/week.

export type Quest = {
	id: string,
	kind: string,
	titleId: string?,
	target: number,
	coins: number,
	gems: number?,
	textKey: string, -- "{target}" is filled in
}

return {
	PerPeriod = 3,
	Daily = {
		{ id = "d_win1", kind = "wins", target = 1, coins = 40, textKey = "QUEST_WINS" },
		{ id = "d_win3", kind = "wins", target = 3, coins = 100, textKey = "QUEST_WINS" },
		{ id = "d_pots10", kind = "pots", target = 10, coins = 50, textKey = "QUEST_POTS" },
		{ id = "d_spin5", kind = "spinPots", target = 5, coins = 60, textKey = "QUEST_SPIN_POTS" },
		{ id = "d_tiger", kind = "title", titleId = "TIGER", target = 1, coins = 50, textKey = "QUEST_TITLE_TIGER" },
		{ id = "d_matches3", kind = "matches", target = 3, coins = 50, textKey = "QUEST_MATCHES" },
	} :: { Quest },
	Weekly = {
		{
			id = "w_dragon2",
			kind = "title",
			titleId = "DRAGON",
			target = 2,
			coins = 300,
			gems = 10,
			textKey = "QUEST_TITLE_DRAGON",
		},
		{ id = "w_wins15", kind = "wins", target = 15, coins = 400, textKey = "QUEST_WINS" },
		{ id = "w_pots80", kind = "pots", target = 80, coins = 300, textKey = "QUEST_POTS" },
		{ id = "w_carp3", kind = "title", titleId = "CARP", target = 3, coins = 250, textKey = "QUEST_TITLE_CARP" },
		{ id = "w_spin40", kind = "spinPots", target = 40, coins = 350, gems = 5, textKey = "QUEST_SPIN_POTS" },
	} :: { Quest },
}
