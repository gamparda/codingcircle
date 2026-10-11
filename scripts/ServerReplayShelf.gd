extends RefCounted
## Server-side shelf of replays that can be fetched with a short code. Two kinds live here:
## replays players uploaded to share (private: only reachable by their code) and every finished online
## match (public: also listed as "recent battles"). The shelf is bounded; the oldest entries fall off first.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const Protocol = preload("res://scripts/NetworkProtocol.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")

const MAX_STORED := 200
const RECENT_LIMIT := 20
const MAX_TEXT := 400_000

var dir := ""
## Oldest first. Each: {code, public, summary, text}
var entries: Array = []
var by_hash: Dictionary = {}
var rng := RandomNumberGenerator.new()
var last_created_usec := 0
var trim_failed := false

func _init() -> void:
	rng.randomize()

func configure(directory: String) -> void:
	dir = "" if directory.is_empty() else directory.path_join("shared_replays")
	entries = []
	by_hash = {}
	last_created_usec = 0
	trim_failed = false
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		if not dir.is_empty():
			DirAccess.make_dir_recursive_absolute(dir)
		return
	var loaded: Array = []
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue
		var path := dir.path_join(file)
		var code := file.get_basename()
		var handle := FileAccess.open(path, FileAccess.READ)
		if handle == null or handle.get_length() > MAX_TEXT * 2 or not Protocol.is_valid_room_code(code):
			continue
		var data = JSON.parse_string(handle.get_as_text())
		handle.close()
		if not data is Dictionary or not data.get("text") is String or not data.get("public", false) is bool:
			continue
		var text: String = data.text.strip_edges()
		var replay := BattleReplay.from_share_text(text) if text.length() <= MAX_TEXT else {}
		if replay.is_empty():
			continue
		# Old shelves have no creation timestamp; keep their modification order as a fallback.
		var created_usec := int(FileAccess.get_modified_time(path)) * 1000000
		var timestamp = data.get("created_usec")
		if (timestamp is int or timestamp is float) and is_finite(float(timestamp)) and float(timestamp) >= 0.0 and float(timestamp) <= 9e15 and float(timestamp) == floorf(float(timestamp)):
			created_usec = int(timestamp)
		loaded.append({"code": code, "public": data.get("public", false), "summary": summarize(replay, code), "text": text, "created_usec": created_usec, "key": _share_key(replay)})
	loaded.sort_custom(func(a, b): return int(a.created_usec) < int(b.created_usec) or (int(a.created_usec) == int(b.created_usec) and String(a.code) < String(b.code)))
	for entry in loaded:
		entries.append(entry)
		# Keep every existing code usable, even when old uploads encode the same content differently.
		if not by_hash.has(entry.key):
			by_hash[entry.key] = entry.code
		last_created_usec = maxi(last_created_usec, int(entry.created_usec))
	_trim()

func _new_code() -> String:
	for _attempt in 50:
		var code := ""
		for _i in Protocol.ROOM_CODE_LENGTH:
			code += Protocol.ROOM_CODE_ALPHABET[rng.randi_range(0, Protocol.ROOM_CODE_ALPHABET.length() - 1)]
		var path := dir.path_join(code + ".json")
		if _find(code) < 0 and (dir.is_empty() or (not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path))):
			return code
	return ""

func _find(code: String) -> int:
	for index in entries.size():
		if entries[index].code == code:
			return index
	return -1

static func summarize(replay: Dictionary, code: String) -> Dictionary:
	var meta: Dictionary = replay.get("meta", {})
	return {"code": code, "winner": int(replay.result.get("winner", -1)), "ticks": int(replay.result.get("ticks", 0)),
		"mode": String(meta.get("mode", "")), "units": [replay.setup.unit_decks[0].duplicate(), replay.setup.unit_decks[1].duplicate()]}

static func _share_key(replay: Dictionary) -> String:
	# Input has already been parsed: JSON numbers now have consistent types, and
	# stringify sorts nested dictionary keys. Preserve notes, clips and all metadata.
	return JSON.stringify(replay, "", true, true).sha256_text()

## Stores share text and returns its code ("" when it is not a valid replay or the shelf cannot take it).
## Persistent shelves issue codes only after a successful disk write.
## Equivalent JSON content gets the same retained code. A public flag set once is never taken back.
func add(text: String, is_public: bool = false) -> String:
	text = text.strip_edges()
	var replay := BattleReplay.from_share_text(text) if text.length() <= MAX_TEXT else {}
	if replay.is_empty():
		return ""
	var key := _share_key(replay)
	if by_hash.has(key):
		var existing := _find(String(by_hash[key]))
		if existing >= 0:
			if is_public and not entries[existing].public:
				var promoted: Dictionary = entries[existing].duplicate(true)
				promoted.public = true
				if not _write(promoted):
					return ""
				entries[existing] = promoted
			return String(entries[existing].code)
	_trim()
	if entries.size() > MAX_STORED:
		return "" # deletion failure may exceed the cap by one, but cannot grow the shelf indefinitely
	var code := _new_code()
	if code.is_empty():
		return ""
	var created_usec := maxi(int(Time.get_unix_time_from_system() * 1000000.0), last_created_usec + 1)
	var entry := {"code": code, "public": is_public, "summary": summarize(replay, code), "text": text, "created_usec": created_usec, "key": key}
	if not _write(entry):
		return ""
	entries.append(entry)
	last_created_usec = created_usec
	by_hash[key] = code
	_trim()
	return code

func _write(entry: Dictionary) -> bool:
	return dir.is_empty() or ServerStats.write_json(dir.path_join(String(entry.code) + ".json"),
		{"public": entry.public, "summary": entry.summary, "text": entry.text, "created_usec": entry.created_usec})

func _trim() -> void:
	while entries.size() > MAX_STORED:
		var gone: Dictionary = entries[0]
		if not dir.is_empty():
			var path := dir.path_join(String(gone.code) + ".json")
			if DirAccess.dir_exists_absolute(path) or (FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK):
				if not trim_failed:
					printerr("REPLAY_SHELF_TRIM_PENDING path=%s" % path)
				trim_failed = true
				return
		entries.pop_front()
		var key: String = gone.get("key", String(gone.text).sha256_text())
		if by_hash.get(key) == gone.code:
			by_hash.erase(key)
			# A legacy duplicate may still be reachable by another code after pruning.
			for entry in entries:
				if entry.get("key", "") == key:
					by_hash[key] = entry.code
					break
	trim_failed = false

func text_for(code: String) -> String:
	var index := _find(code)
	return "" if index < 0 else String(entries[index].text)

## Newest public matches first.
func recent() -> Array:
	var list: Array = []
	for index in range(entries.size() - 1, -1, -1):
		if entries[index].public:
			list.append(entries[index].summary)
			if list.size() >= RECENT_LIMIT:
				break
	return list
