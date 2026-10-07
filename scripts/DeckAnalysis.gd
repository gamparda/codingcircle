extends RefCounted
## Aggregates saved replays into per-deck statistics. Only battles where the human always sits on the
## blue side count (campaign, practice, daily challenge), so "my deck" is unambiguous.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const DeckSimulator = preload("res://scripts/DeckSimulator.gd")
const OWN_MODES := ["campaign", "practice", "daily"]

## Rows sorted by games played (then win rate). Each row: deck, games, wins, losses, draws, win_rate,
## average_seconds, hardest_stage {stage, rate, games} or {}, tips.
static func collect(paths: Array) -> Array:
	var groups := {}
	for path in paths:
		var replay := BattleReplay.load_file(String(path))
		if replay.is_empty() or not OWN_MODES.has(String(replay.get("meta", {}).get("mode", ""))):
			continue
		var deck: Array = replay.setup.unit_decks[0]
		var sorted_deck: Array = deck.duplicate()
		sorted_deck.sort()
		var key := ",".join(PackedStringArray(sorted_deck))
		if not groups.has(key):
			groups[key] = {"deck": deck.duplicate(), "results": [], "stages": {}}
		var winner := int(replay.result.get("winner", -1))
		var outcome := "win" if winner == 0 else ("loss" if winner == 1 else ("draw" if winner == 2 else "timeout"))
		var stage := int(replay.get("meta", {}).get("stage", replay.get("ai", {}).get("stage", 0)))
		groups[key].results.append({"result": outcome, "seconds": float(replay.result.get("elapsed", 0.0)), "base": 0.0, "enemy_base": 0.0, "kills": 0, "damage": 0.0})
		if stage > 0:
			var entry: Array = groups[key].stages.get(stage, [0, 0])
			entry[1] += 1
			if outcome == "win":
				entry[0] += 1
			groups[key].stages[stage] = entry
	var rows: Array = []
	for key in groups:
		var group: Dictionary = groups[key]
		var summary: Dictionary = DeckSimulator.DeckSimulatorSummary.build(group.results, group.deck, 0)
		var hardest := {}
		for stage in group.stages:
			var rate := float(group.stages[stage][0]) / float(group.stages[stage][1])
			if hardest.is_empty() or rate < float(hardest.rate) or (rate == float(hardest.rate) and int(stage) > int(hardest.stage)):
				hardest = {"stage": int(stage), "rate": rate, "games": int(group.stages[stage][1])}
		rows.append({"deck": group.deck, "games": int(summary.matches), "wins": int(summary.wins), "losses": int(summary.losses),
			"draws": int(summary.draws), "win_rate": float(summary.win_rate), "average_seconds": float(summary.average_seconds),
			"hardest_stage": hardest, "tips": summary.tips})
	rows.sort_custom(func(a, b): return int(a.games) > int(b.games) or (int(a.games) == int(b.games) and float(a.win_rate) > float(b.win_rate)))
	return rows
