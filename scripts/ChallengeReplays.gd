extends RefCounted
## Read-only lookup of shelved challenge battles. A date/time match is not a battle ID.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")

static func ruleset_of(replay: Dictionary) -> String:
	var value = replay.get("meta", {}).get("ruleset", "0")
	return String(value) if ServerStats.valid_ruleset(value) else "0"

static func belongs_to(replay: Dictionary, period: String, date: String, ruleset: String) -> bool:
	var meta: Dictionary = replay.get("meta", {})
	if String(meta.get("mode", "")) != "daily" or String(meta.get("date", "")) != date:
		return false
	if String(meta.get("period", "daily")) != period:
		return false
	var rule := ruleset_of(replay)
	# Legacy metadata cannot establish a version. Never include a known different version.
	return rule == "0" or rule == ruleset

static func load_saved(with_analysis: bool = false) -> Array:
	var entries: Array = []
	for path in BattleReplay.list_saved(false):
		var replay := BattleReplay.load_file(String(path))
		if replay.is_empty() or String(replay.get("meta", {}).get("mode", "")) != "daily":
			continue
		entries.append(shelf_entry(String(path), replay, with_analysis))
	sort_entries(entries)
	return entries

static func shelf_entry(path: String, replay: Dictionary, with_analysis: bool = false, with_fingerprint: bool = true) -> Dictionary:
	# Keep only display/matching metadata, rather than every battle's command log.
	var entry := {"path": path, "order": BattleReplay._storage_order(replay),
		"replay": {"meta": replay.get("meta", {}).duplicate(true), "result": replay.result.duplicate(true),
			"clip": BattleReplay.clip_of(replay), "hz": replay.hz}}
	if with_fingerprint: entry["fingerprint"] = fingerprint(replay)
	if with_analysis:
		entry["analysis_fingerprint"] = analysis_fingerprint(replay)
		entry.replay["setup"] = {"unit_decks": replay.setup.unit_decks.duplicate(true),
			"structure_decks": replay.setup.structure_decks.duplicate(true)}
	return entry

static func sort_entries(entries: Array) -> void:
	entries.sort_custom(func(a, b): return int(a.order) > int(b.order) or (int(a.order) == int(b.order) and String(a.path) > String(b.path)))

static func fingerprint(replay: Dictionary) -> String:
	return JSON.stringify(replay, "", true).sha256_text()

## Notes do not affect replay simulation or scoring. Keep strict full-file checks for
## starting playback/analysis, but reuse completed scores after saving only notes.
static func analysis_fingerprint(replay: Dictionary) -> String:
	var battle := replay.duplicate()
	battle.erase("notes")
	battle.erase("_local_protected")
	return fingerprint(battle)

static func matching(entries: Array, period: String, date: String, ruleset: String) -> Array:
	return entries.filter(func(entry): return belongs_to(entry.replay, period, date, ruleset))

static func same_time_and_outcome(replay: Dictionary, record: Dictionary) -> bool:
	var result: Dictionary = replay.get("result", {})
	var winner := int(result.get("winner", -1))
	var outcome_matches := winner == 0 if bool(record.get("won", false)) else winner in [1, 2]
	return outcome_matches and absf(float(result.get("elapsed", 0.0)) - float(record.get("seconds", 0.0))) < 0.001

## Only a reproduced terminal state can supply the missing final base health.
## A matching hash does not establish which scoring rules an old file used.
static func score_analysis(replay: Dictionary, player: BattleReplay.Player, record: Dictionary, record_ruleset: String) -> Dictionary:
	var played := player.summary()
	var result: Dictionary = replay.result
	if int(played.winner) not in [0, 1, 2] or String(played.state_hash) != String(result.state_hash) or int(played.winner) != int(result.winner) or int(played.ticks) != int(result.ticks) or absf(float(played.elapsed) - float(result.elapsed)) >= 0.001:
		return {"ok": false}
	var current := ServerStats.ruleset_id()
	var known_current := current != "0" and ruleset_of(replay) == current
	var comparable := known_current and record_ruleset == current
	var won := int(played.winner) == 0
	var health := float(player.model.base_hp[0])
	var breakdown := DailyChallenge.score_breakdown(won, health, float(played.elapsed))
	return {"ok": true, "won": won, "health": health, "seconds": float(played.elapsed),
		"breakdown": breakdown, "known_current": known_current, "comparable": comparable,
		"difference": int(breakdown.score) - int(record.get("score", 0)),
		"record_matches": comparable and same_time_and_outcome(replay, record) and int(breakdown.score) == int(record.get("score", 0))}
