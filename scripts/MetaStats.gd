extends RefCounted
## Client side of the community statistics: what the server last told us (cached on disk per ruleset),
## the anonymous install id, and the queue of results waiting to be shared once a server is reachable.
## Sharing is opt-in (settings.share_results); reading the statistics never needs it.

const ServerStats = preload("res://scripts/ServerStats.gd")
const ServerDailyBoard = preload("res://scripts/ServerDailyBoard.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")

const CACHE_PATH := "user://meta_stats.json"
const MAX_PENDING := 20
const REPORT_MODES := ["campaign", "practice", "daily"]

static var snapshot: Dictionary = {}
static var boards: Dictionary = {}
static var cache_path := CACHE_PATH

# ---------- statistics snapshot ----------

static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("ruleset") is String or data.size() > 8:
		return false
	for source in ServerStats.SOURCES:
		var section = data.get(source)
		if not section is Dictionary or not section.get("top") is Array or not section.get("lookup") is Dictionary:
			return false
		if section.top.size() > ServerStats.TOP_COMBOS or section.lookup.size() > ServerStats.MAX_LOOKUP:
			return false
	return true

static func store(data: Dictionary) -> void:
	if not valid_snapshot(data):
		return
	if not snapshot.is_empty() and String(snapshot.ruleset) == String(data.ruleset):
		# Lookups accumulate: keep rows for decks asked about earlier.
		for source in ServerStats.SOURCES:
			var merged: Dictionary = snapshot[source].lookup.duplicate()
			merged.merge(data[source].lookup, true)
			data[source].lookup = merged
	snapshot = data
	ServerStats.write_json(cache_path, data)

static func load_cache() -> void:
	var loaded = ServerStats.read_json(cache_path)
	snapshot = loaded if valid_snapshot(loaded) and String(loaded.ruleset) == ServerStats.ruleset_id() else {}

static func current() -> Dictionary:
	if snapshot.is_empty():
		load_cache()
	return snapshot

## {"games", "wins", "draws"} for a unit deck from the online statistics, or {} when unknown.
static func deck_record(units: Array) -> Dictionary:
	var data := current()
	if data.is_empty():
		return {}
	var key := ServerStats.deck_key(units)
	var row = data.online.lookup.get(key)
	if row == null:
		for entry in data.online.top:
			if ServerStats.deck_key(entry.deck) == key:
				row = entry
	return {} if row == null else {"games": int(row.games), "wins": int(row.wins), "draws": int(row.draws)}

static func record_text(record: Dictionary) -> String:
	if record.is_empty():
		return "전체 플레이어 기록 없음"
	var rate := roundi(100.0 * float(record.wins) / maxf(1.0, float(record.games)))
	var text := "전체 플레이어 승률 %d%% (%d판)" % [rate, int(record.games)]
	if int(record.games) < ServerStats.MIN_SAMPLES:
		text += " · 표본 부족"
	return text

# ---------- identity and opt-in ----------

static func install_id(save: Dictionary) -> String:
	if not ServerDailyBoard.valid_id(String(save.get("install_id", ""))):
		var crypto := Crypto.new()
		save["install_id"] = crypto.generate_random_bytes(16).hex_encode()
	return String(save.install_id)

static func sharing(save: Dictionary) -> bool:
	return bool(save.get("settings", {}).get("share_results", false))

# ---------- queue ----------

## Remembers a finished solo battle (own decks + outcome) for the next time a server is reachable.
static func queue_report(save: Dictionary, units: Array, structures: Array, result: int, mode: String) -> bool:
	if not sharing(save) or not REPORT_MODES.has(mode):
		return false
	var pending: Array = save.get("pending_reports", [])
	if pending.size() >= MAX_PENDING:
		pending.pop_front()
	pending.append({"units": units.duplicate(), "structures": structures.duplicate(), "result": result, "mode": mode})
	save["pending_reports"] = pending
	return true

## Keeps only the best unsent daily score.
static func queue_daily(save: Dictionary, date: String, score: int, seconds: float) -> bool:
	if not sharing(save):
		return false
	var current_entry: Dictionary = save.get("pending_daily", {})
	if current_entry.get("date") == date and int(current_entry.get("score", 0)) >= score:
		return false
	save["pending_daily"] = {"date": date, "score": score, "seconds": seconds}
	return true

## Sends everything queued over an open connection and clears it. `network` is the NetworkController.
static func flush(save: Dictionary, network) -> void:
	if not network.client_is_online():
		return
	if sharing(save):
		for report in save.get("pending_reports", []):
			network.send_result_report(report.units, report.structures, int(report.result), String(report.mode))
		var daily: Dictionary = save.get("pending_daily", {})
		if not daily.is_empty():
			network.send_daily_score(String(daily.date), install_id(save), String(save.get("nickname", "")), int(daily.score), float(daily.seconds))
	save["pending_reports"] = []
	save["pending_daily"] = {}

static func valid_board(data: Variant) -> bool:
	if not data is Dictionary or not data.get("date") is String or not data.get("entries") is Array or data.entries.size() > ServerDailyBoard.TOP:
		return false
	for entry in data.entries:
		if not entry is Dictionary or not entry.get("nick") is String or not (entry.get("score") is int or entry.get("score") is float):
			return false
	return data.get("total") is int or data.get("total") is float
