extends RefCounted
## Player reports, appended one JSON object per line to <state>/reports.jsonl for the operator to review.
## A report names the reporter's account, the reported player (account when signed in, and the nickname shown
## in that match), the match and a reason. Each account may report each match once and at most DAILY_LIMIT
## times a day. Reports older than KEEP_SECONDS are deleted (prune, run daily with the backups).

const FILE_NAME := "reports.jsonl"
const REASONS := ["nickname", "manner", "cheat"]
const DAILY_LIMIT := 10
const KEEP_SECONDS := 365 * 86400

var path := ""
## reporter account id -> {"day": String, "count": int, "matches": {match key: true}}
var recent: Dictionary = {}

func configure(directory: String) -> void:
	path = "" if directory.is_empty() else directory.path_join(FILE_NAME)
	recent = {}

## Returns "" when stored, or "invalid_reason" | "already_reported" | "limit" | "storage".
func add(reporter: String, target: Dictionary, match_key: String, reason: String, now: int) -> String:
	if reason not in REASONS:
		return "invalid_reason"
	var day := Time.get_date_string_from_unix_time(now)
	var mine: Dictionary = recent.get(reporter, {})
	if String(mine.get("day", "")) != day:
		mine = {"day": day, "count": 0, "matches": {}}
	if mine.matches.has(match_key):
		return "already_reported"
	if int(mine.count) >= DAILY_LIMIT:
		return "limit"
	var entry := {"at": now, "reporter": reporter, "target_account": String(target.get("account", "")), "target_nickname": String(target.get("nickname", "")), "match": match_key, "reason": reason}
	if path.is_empty() or not _append(JSON.stringify(entry)):
		return "storage"
	mine.count = int(mine.count) + 1
	mine.matches[match_key] = true
	recent[reporter] = mine
	print("PLAYER_REPORT reason=%s match=%s" % [reason, match_key])
	return ""

## Rewrites the file without reports older than KEEP_SECONDS. Returns how many were removed.
func prune(now: int) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return 0
	var kept: Array = []
	var removed := 0
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var entry = JSON.parse_string(line)
		if entry is Dictionary and (entry.get("at") is float or entry.get("at") is int) and now - int(entry.at) > KEEP_SECONDS:
			removed += 1
		else:
			kept.append(line)
	if removed == 0:
		return 0
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return 0
	file.store_string("\n".join(kept) + ("\n" if not kept.is_empty() else ""))
	file.close()
	if DirAccess.rename_absolute(temp, path) != OK:
		DirAccess.remove_absolute(temp)
		return 0
	print("REPORTS_PRUNED count=%d" % removed)
	return removed

func _append(line: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_string(line + "\n")
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok
