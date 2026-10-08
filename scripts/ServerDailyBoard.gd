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
var path := ""
var dirty := false
var verifier: Callable = Callable()

func configure(directory: String) -> void:
	path = "" if directory.is_empty() else directory.path_join("daily_board.json")
	days = {}
	var loaded = ServerStats.read_json(path)
	if loaded is Dictionary:
		for date in loaded:
			if _valid_date(String(date)) and loaded[date] is Dictionary:
				days[String(date)] = loaded[date]
	dirty = false

static func _valid_date(date: String) -> bool:
	return date.length() == 8 and date.is_valid_int()

static func valid_id(value: String) -> bool:
	if value.length() != 32:
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true

## Only today's and yesterday's challenge (UTC) can still be submitted.
static func accepts_date(date: String, today: String) -> bool:
	if not _valid_date(date) or not _valid_date(today):
		return false
	var yesterday := DailyChallenge.date_key(DailyChallenge._to_unix(today) - 86400)
	return date == today or date == yesterday

func submit(date: String, id: String, nickname: String, score: int, seconds: float, today: String = "") -> bool:
	var now_key := today if not today.is_empty() else DailyChallenge.date_key()
	if not accepts_date(date, now_key) or not valid_id(id) or score < MIN_SCORE or score > MAX_SCORE:
		return false
	if not preload("res://scripts/RoomSessions.gd").safe_text(nickname, 16) or not is_finite(seconds) or seconds < 0.0 or seconds > MAX_SECONDS:
		return false
	var entry := {"nick": nickname.strip_edges(), "score": score, "seconds": snappedf(seconds, 0.1)}
	if verifier.is_valid() and not bool(verifier.call(date, entry)):
		return false
	var day: Dictionary = days.get(date, {})
	if not day.has(id) and day.size() >= MAX_PER_DAY:
		return false
	var previous: Dictionary = day.get(id, {})
	if not previous.is_empty() and int(previous.score) >= score:
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
		if String(date) < cutoff:
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
	return {"date": date, "total": ranked.size(), "entries": entries, "rank": rank, "mine": mine}

func flush() -> void:
	if path.is_empty() or not dirty:
		return
	if ServerStats.write_json(path, days):
		dirty = false
