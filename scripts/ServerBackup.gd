extends RefCounted
## Daily copies of the server's player data (accounts, cloud saves, reports, statistics, leaderboards) under
## <state>/backups/<YYYY-MM-DD>/, keeping the last KEEP_DAYS. Replay archives are not copied: they are many,
## large and can be rebuilt from nothing a player owns. Also restores a store whose file cannot be read, so a
## damaged file is set aside instead of being overwritten with an empty store.

const ServerStats = preload("res://scripts/ServerStats.gd")

const DIR_NAME := "backups"
const KEEP_DAYS := 14
## Top-level folders copied whole (one file per account).
const FOLDERS := ["saves"]

## Copies today's data once. Returns the backup folder, or "" when today's copy already exists or failed.
static func snapshot(state_dir: String, now: int) -> String:
	if state_dir.is_empty():
		return ""
	var day := Time.get_date_string_from_unix_time(now)
	var root := state_dir.path_join(DIR_NAME)
	var target := root.path_join(day)
	if DirAccess.dir_exists_absolute(target):
		return ""
	var staging := target + ".partial"
	_remove_tree(staging)
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		printerr("BACKUP_FAILED day=%s reason=mkdir" % day)
		return ""
	var ok := true
	for file in DirAccess.get_files_at(state_dir):
		if _backed_up(file):
			ok = DirAccess.copy_absolute(state_dir.path_join(file), staging.path_join(file)) == OK and ok
	for folder in FOLDERS:
		if DirAccess.dir_exists_absolute(state_dir.path_join(folder)):
			ok = _copy_tree(state_dir.path_join(folder), staging.path_join(folder)) and ok
	if not ok or DirAccess.rename_absolute(staging, target) != OK:
		_remove_tree(staging)
		printerr("BACKUP_FAILED day=%s reason=copy" % day)
		return ""
	_prune(root)
	print("BACKUP_DONE day=%s" % day)
	return target

## Store files that hold player data. Temporary and damaged copies stay out.
static func _backed_up(file: String) -> bool:
	return (file.ends_with(".json") or file.ends_with(".jsonl")) and not file.contains(".corrupt-")

## Newest copies first.
static func days(state_dir: String) -> Array:
	var root := state_dir.path_join(DIR_NAME)
	var found: Array = []
	for name in DirAccess.get_directories_at(root):
		if name.length() == 10 and not name.ends_with(".partial"):
			found.append(name)
	found.sort()
	found.reverse()
	return found

static func _prune(root: String) -> void:
	var state_dir := root.get_base_dir()
	var all := days(state_dir)
	for index in range(KEEP_DAYS, all.size()):
		_remove_tree(root.path_join(String(all[index])))

## Reads a JSON store. A file that exists but cannot be parsed is renamed to <file>.corrupt-<time> and the
## newest readable backup of it is restored in its place; the result says what happened.
## Returns {"value": Variant (null when there is nothing), "restored_from": day or "", "corrupt": path or ""}.
static func read_store(path: String, now: int = -1) -> Dictionary:
	var result := {"value": null, "restored_from": "", "corrupt": ""}
	if path.is_empty() or not FileAccess.file_exists(path):
		return result
	var value = ServerStats.read_json(path)
	if value is Dictionary or value is Array:
		result.value = value
		return result
	var stamp := now if now >= 0 else int(Time.get_unix_time_from_system())
	result.corrupt = "%s.corrupt-%d" % [path, stamp]
	DirAccess.rename_absolute(path, result.corrupt)
	printerr("STORE_CORRUPT file=%s kept=%s" % [path.get_file(), result.corrupt.get_file()])
	var state_dir := path.get_base_dir()
	for day in days(state_dir):
		var copy := state_dir.path_join(DIR_NAME).path_join(String(day)).path_join(path.get_file())
		var restored = ServerStats.read_json(copy)
		if (restored is Dictionary or restored is Array) and DirAccess.copy_absolute(copy, path) == OK:
			result.value = restored
			result.restored_from = String(day)
			printerr("STORE_RESTORED file=%s from=%s" % [path.get_file(), day])
			return result
	printerr("STORE_NOT_RESTORED file=%s: no readable backup" % path.get_file())
	return result

static func _copy_tree(source: String, target: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return false
	var ok := true
	for file in DirAccess.get_files_at(source):
		if not file.ends_with(".tmp"):
			ok = DirAccess.copy_absolute(source.path_join(file), target.path_join(file)) == OK and ok
	for folder in DirAccess.get_directories_at(source):
		ok = _copy_tree(source.path_join(folder), target.path_join(folder)) and ok
	return ok

static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for folder in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	DirAccess.remove_absolute(path)
