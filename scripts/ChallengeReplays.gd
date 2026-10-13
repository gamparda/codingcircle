extends RefCounted
## Read-only lookup of shelved challenge battles. A date/time match is not a battle ID.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")

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

static func load_saved() -> Array:
	var entries: Array = []
	for path in BattleReplay.list_saved(false):
		var replay := BattleReplay.load_file(String(path))
		if replay.is_empty() or String(replay.get("meta", {}).get("mode", "")) != "daily":
			continue
		# Keep only display/matching metadata, rather than every battle's command log.
		entries.append({"path": String(path), "order": BattleReplay._storage_order(replay), "fingerprint": fingerprint(replay),
			"replay": {"meta": replay.get("meta", {}).duplicate(true), "result": replay.result.duplicate(true),
				"clip": BattleReplay.clip_of(replay), "hz": replay.hz}})
	entries.sort_custom(func(a, b): return int(a.order) > int(b.order) or (int(a.order) == int(b.order) and String(a.path) > String(b.path)))
	return entries

static func fingerprint(replay: Dictionary) -> String:
	return JSON.stringify(replay, "", true).sha256_text()

static func matching(entries: Array, period: String, date: String, ruleset: String) -> Array:
	return entries.filter(func(entry): return belongs_to(entry.replay, period, date, ruleset))

static func same_time_and_outcome(replay: Dictionary, record: Dictionary) -> bool:
	var result: Dictionary = replay.get("result", {})
	var winner := int(result.get("winner", -1))
	var outcome_matches := winner == 0 if bool(record.get("won", false)) else winner in [1, 2]
	return outcome_matches and absf(float(result.get("elapsed", 0.0)) - float(record.get("seconds", 0.0))) < 0.001
