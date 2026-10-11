extends RefCounted
## Daily challenge leaderboard. Scores are accepted as the client reports them (after cheap sanity checks);
## set `verifier` to a Callable(date, entry) -> bool to start re-checking submissions later.

const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")

const KEEP_DAYS := 14
const TOP := 10
const MAX_PER_DAY := 5000
const MIN_SCORE := 100
const MAX_SCORE := 3000
const MAX_SECONDS := 3600.0

var days: Dictionary = {}
var ruleset := ServerStats.ruleset_id()
var path := ""
var dirty := false
var verifier: Callable = Callable()

func configure(directory: String, rule: String = "") -> void:
	ruleset = rule if ServerStats.valid_ruleset(rule) else ServerStats.ruleset_id()
	# Legacy boards have no reliable originating version; leave them untouched.
	path = "" if directory.is_empty() else directory.path_join("daily_board_%s.json" % ruleset)
	days = {}
	var loaded = ServerStats.read_json(path)
	if loaded is Dictionary:
		for date in loaded:
			if date is String and _valid_date(date) and loaded[date] is Dictionary:
				var day := {}
				for id in loaded[date]:
					var entry = loaded[date][id]
					if id is String and valid_id(id) and valid_entry(entry) and day.size() < MAX_PER_DAY:
						day[id] = {"nick": entry.nick.strip_edges(), "score": int(entry.score), "seconds": float(entry.seconds)}
				days[date] = day
	dirty = false

static func _valid_date(date: String) -> bool:
	return valid_date(date)

## "YYYYMMDD" for a daily board, "wYYYYMMDD" (the Monday) for a weekly one.
static func valid_date(date: String) -> bool:
	var digits := date.trim_prefix("w")
	if digits.length() != 8:
		return false
	for character in digits:
		if not "0123456789".contains(character):
			return false
	var year := int(digits.substr(0, 4))
	var month := int(digits.substr(4, 2))
	var day := int(digits.substr(6, 2))
	if year < 1 or month < 1 or month > 12 or day < 1:
		return false
	var month_days := [31, 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return day <= month_days[month - 1] and (not date.begins_with("w") or DailyChallenge.week_key(DailyChallenge._to_unix(digits)) == digits)

static func valid_entry(entry: Variant) -> bool:
	if not entry is Dictionary or not entry.get("nick") is String:
		return false
	return preload("res://scripts/RoomSessions.gd").safe_text(entry.nick, 16) and valid_score(entry.get("score"), entry.get("seconds"))

## Queuing, loading and server submission must agree; never turn a malformed
## completion time into a legitimate zero-second result.
static func valid_score(points: Variant, seconds: Variant) -> bool:
	return ServerStats.valid_count(points) and int(points) >= MIN_SCORE and int(points) <= MAX_SCORE and (seconds is int or seconds is float) and is_finite(float(seconds)) and float(seconds) >= 0.0 and float(seconds) <= MAX_SECONDS

static func valid_id(value: String) -> bool:
	return ServerStats.valid_report_id(value)

## Only today's and yesterday's challenge (UTC) can still be submitted.
static func accepts_date(date: String, today: String) -> bool:
	if not _valid_date(date) or not _valid_date(today):
		return false
	var now := DailyChallenge._to_unix(today)
	if date.begins_with("w"):
		return date == "w" + DailyChallenge.week_key(now) or date == "w" + DailyChallenge.week_key(now - 7 * 86400)
	return date == today or date == DailyChallenge.date_key(now - 86400)

func submit(date: String, id: String, nickname: String, score: int, seconds: float, today: String = "") -> bool:
	var now_key := today if not today.is_empty() else DailyChallenge.date_key()
	if not accepts_date(date, now_key) or not valid_id(id) or not valid_score(score, seconds):
		return false
	if not preload("res://scripts/RoomSessions.gd").safe_text(nickname, 16):
		return false
	var entry := {"nick": nickname.strip_edges(), "score": score, "seconds": snappedf(seconds, 0.1)}
	if verifier.is_valid() and not bool(verifier.call(date, entry)):
		return false
	var day: Dictionary = days.get(date, {})
	if not day.has(id) and day.size() >= MAX_PER_DAY:
		return false
	var previous: Dictionary = day.get(id, {})
	if not DailyChallenge.better_result(score, float(entry.seconds), previous):
		previous.nick = entry.nick
		day[id] = previous
	else:
		day[id] = entry
	days[date] = day
	_prune(now_key)
	dirty = true
	flush()
	return true

func _prune(today: String) -> void:
	var cutoff := DailyChallenge.date_key(DailyChallenge._to_unix(today) - KEEP_DAYS * 86400)
	for date in days.keys():
		if String(date).trim_prefix("w") < cutoff:
			days.erase(date)

## {"date", "total", "entries": [{nick, score, seconds}], "rank": 0 when not on the board, "mine": score}
func board(date: String, id: String = "") -> Dictionary:
	var day: Dictionary = days.get(date, {})
	var ranked: Array = []
	for key in day:
		ranked.append({"id": key, "nick": day[key].nick, "score": int(day[key].score), "seconds": float(day[key].seconds)})
	ranked.sort_custom(func(a, b): return int(a.score) > int(b.score) or (int(a.score) == int(b.score) and float(a.seconds) < float(b.seconds)))
	var entries: Array = []
	var rank := 0
	var mine := 0
	for index in ranked.size():
		if String(ranked[index].id) == id:
			rank = index + 1
			mine = int(ranked[index].score)
		if index < TOP:
			entries.append({"nick": ranked[index].nick, "score": ranked[index].score, "seconds": ranked[index].seconds})
	return {"date": date, "ruleset": ruleset, "total": ranked.size(), "entries": entries, "rank": rank, "mine": mine}

func flush() -> void:
	if path.is_empty() or not dirty:
		return
	if ServerStats.write_json(path, days):
		dirty = false
