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
	if not ServerStats.valid_count(data.get("min_samples")) or int(data.min_samples) <= 0:
		return false
	for source in ServerStats.SOURCES:
		var section = data.get(source)
		if not section is Dictionary or not section.get("top") is Array or not section.get("lookup") is Dictionary:
			return false
		if not ServerStats.valid_count(section.get("matches")) or section.top.size() > ServerStats.TOP_COMBOS or section.lookup.size() > ServerStats.MAX_LOOKUP:
			return false
		for row in section.top:
			if not _valid_row(row, int(section.matches)):
				return false
		for key in section.lookup:
			var row = section.lookup[key]
			if not key is String or not _valid_row(row, int(section.matches)) or ServerStats.deck_key(row.deck) != key:
				return false
		for group in ["units", "structures"]:
			if not section.get(group) is Dictionary or section[group].size() > ServerStats.MAX_COMBOS:
				return false
			for key in section[group]:
				var entry = section[group][key]
				if not ServerStats.valid_group_key(group, key) or not ServerStats.valid_counts(entry) or int(entry.games) > int(section.matches):
					return false
	return true

static func _valid_row(row: Variant, matches: int) -> bool:
	if not ServerStats.valid_counts(row) or not ServerStats.valid_unit_deck(row.get("deck")) or int(row.games) > matches:
		return false
	var confidence = row.get("score")
	return (confidence is int or confidence is float) and is_finite(float(confidence)) and float(confidence) >= 0.0 and float(confidence) <= 1.0

static func store(data: Dictionary) -> void:
	if not valid_snapshot(data):
		return
	data = data.duplicate(true)
	if not snapshot.is_empty() and String(snapshot.ruleset) == String(data.ruleset):
		# Keep recently requested decks within the same bound used when reading the cache.
		for source in ServerStats.SOURCES:
			# A lower total means the server store was reset; discard its previous lookups.
			var merged: Dictionary = snapshot[source].lookup.duplicate() if int(data[source].matches) >= int(snapshot[source].matches) else {}
			for key in data[source].lookup:
				merged.erase(key)
				merged[key] = data[source].lookup[key]
			while merged.size() > ServerStats.MAX_LOOKUP:
				merged.erase(merged.keys()[0])
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

## "선택 34% · 승률 52%" for one unit or structure kind, or "" while the sample is too small to mean anything.
## `group` is "units" or "structures".
static func kind_text(group: String, kind: String) -> String:
	var data := current()
	if data.is_empty() or int(data.online.matches) <= 0:
		return ""
	var entry = data.online[group].get(kind)
	if entry == null or int(entry.games) < ServerStats.MIN_SAMPLES:
		return ""
	return "선택 %d%% · 승률 %d%%" % [roundi(100.0 * float(entry.games) / float(data.online.matches)), roundi(100.0 * float(entry.wins) / float(entry.games))]

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

## Keeps the best unsent score for each board (a few at most: today, this week).
static func queue_daily(save: Dictionary, date: String, score: int, seconds: float) -> bool:
	if not sharing(save):
		return false
	var pending: Dictionary = save.get("pending_daily", {})
	if not DailyChallenge.better_result(score, seconds, pending.get(date, {})):
		return false
	pending[date] = {"score": score, "seconds": seconds}
	while pending.size() > 4:
		pending.erase(pending.keys()[0])
	save["pending_daily"] = pending
	return true

## Sends everything queued over an open connection and clears it. `network` is the NetworkController.
static func flush(save: Dictionary, network) -> void:
	if not network.client_is_online():
		return
	if sharing(save):
		for report in save.get("pending_reports", []):
			network.send_result_report(report.units, report.structures, int(report.result), String(report.mode))
		var pending: Dictionary = save.get("pending_daily", {})
		for date in pending:
			network.send_daily_score(String(date), install_id(save), String(save.get("nickname", "")), int(pending[date].score), float(pending[date].seconds))
	save["pending_reports"] = []
	save["pending_daily"] = {}

static func valid_board(data: Variant) -> bool:
	if not data is Dictionary or not data.get("date") is String or not ServerDailyBoard.valid_date(data.date) or not data.get("entries") is Array or data.entries.size() > ServerDailyBoard.TOP:
		return false
	for key in ["total", "rank", "mine"]:
		if not ServerStats.valid_count(data.get(key)):
			return false
	if int(data.total) > ServerDailyBoard.MAX_PER_DAY or data.entries.size() != mini(ServerDailyBoard.TOP, int(data.total)) or int(data.rank) > int(data.total):
		return false
	for entry in data.entries:
		if not ServerDailyBoard.valid_entry(entry):
			return false
	return int(data.mine) == 0 if int(data.rank) == 0 else int(data.mine) >= ServerDailyBoard.MIN_SCORE and int(data.mine) <= ServerDailyBoard.MAX_SCORE
