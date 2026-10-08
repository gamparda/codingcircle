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

func _init() -> void:
	rng.randomize()

func configure(directory: String) -> void:
	dir = "" if directory.is_empty() else directory.path_join("shared_replays")
	entries = []
	by_hash = {}
	if dir.is_empty() or not DirAccess.dir_exists_absolute(dir):
		if not dir.is_empty():
			DirAccess.make_dir_recursive_absolute(dir)
		return
	var loaded: Array = []
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue
		var path := dir.path_join(file)
		var data = ServerStats.read_json(path)
		var code := file.get_basename()
		if data is Dictionary and Protocol.is_valid_room_code(code) and data.get("text") is String and data.get("summary") is Dictionary:
			loaded.append({"code": code, "public": bool(data.get("public", false)), "summary": data.summary, "text": data.text, "modified": FileAccess.get_modified_time(path)})
	loaded.sort_custom(func(a, b): return int(a.modified) < int(b.modified))
	for entry in loaded:
		entry.erase("modified")
		entries.append(entry)
		by_hash[hash(entry.text)] = entry.code

func _new_code() -> String:
	for _attempt in 50:
		var code := ""
		for _i in Protocol.ROOM_CODE_LENGTH:
			code += Protocol.ROOM_CODE_ALPHABET[rng.randi_range(0, Protocol.ROOM_CODE_ALPHABET.length() - 1)]
		if _find(code) < 0:
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

## Stores share text and returns its code ("" when it is not a valid replay or the shelf cannot take it).
## The same text always gets the same code. A public flag set once is never taken back.
func add(text: String, is_public: bool = false) -> String:
	var replay := BattleReplay.from_share_text(text) if text.length() <= MAX_TEXT else {}
	if replay.is_empty():
		return ""
	var key := hash(text)
	if by_hash.has(key):
		var existing := _find(String(by_hash[key]))
		if existing >= 0:
			if is_public and not entries[existing].public:
				entries[existing].public = true
				_write(entries[existing])
			return String(entries[existing].code)
	var code := _new_code()
	if code.is_empty():
		return ""
	var entry := {"code": code, "public": is_public, "summary": summarize(replay, code), "text": text.strip_edges()}
	entries.append(entry)
	by_hash[key] = code
	_write(entry)
	_trim()
	return code

func _write(entry: Dictionary) -> void:
	if not dir.is_empty():
		ServerStats.write_json(dir.path_join(String(entry.code) + ".json"), {"public": entry.public, "summary": entry.summary, "text": entry.text})

func _trim() -> void:
	while entries.size() > MAX_STORED:
		var gone: Dictionary = entries.pop_front()
		by_hash.erase(hash(gone.text))
		if not dir.is_empty():
			DirAccess.remove_absolute(dir.path_join(String(gone.code) + ".json"))

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
