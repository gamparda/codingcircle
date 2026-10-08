extends RefCounted
## Anonymous aggregate deck statistics kept by the server, one file per ruleset version.
## Two sources are counted apart so that either can be dropped or audited later without
## touching the other: "online" (decided by the server's own simulation) and "reported"
## (results the clients tell the server about; currently trusted as sent).

const Protocol = preload("res://scripts/NetworkProtocol.gd")

const SOURCES := ["online", "reported"]
const MIN_SAMPLES := 20
const TOP_COMBOS := 8
const MAX_LOOKUP := 12
const MAX_COMBOS := 4000
const SAVE_INTERVAL_MSEC := 30000

var ruleset := ""
var path := ""
var data: Dictionary = {}
var dirty := false
var last_save_msec := 0

func _init() -> void:
	data = _empty()
	ruleset = ruleset_id()

static func _empty() -> Dictionary:
	var result := {}
	for source in SOURCES:
		result[source] = {"matches": 0, "combos": {}, "units": {}, "structures": {}}
	return result

static func ruleset_id() -> String:
	var file := FileAccess.open("res://build_info.json", FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary and parsed.get("content_version") is String:
			return String(parsed.content_version)
	return "0"

## Points the store at a directory (empty = memory only) and loads what is already there.
func configure(directory: String, rule: String = "") -> void:
	ruleset = rule if not rule.is_empty() else ruleset_id()
	path = "" if directory.is_empty() else directory.path_join("stats_%s.json" % ruleset)
	data = _empty()
	var loaded = read_json(path)
	if loaded is Dictionary:
		for source in SOURCES:
			if loaded.get(source) is Dictionary:
				data[source] = _sanitize_section(loaded[source])
	dirty = false

static func _sanitize_section(raw: Dictionary) -> Dictionary:
	var clean: Dictionary = _empty()["online"]
	clean.matches = maxi(0, int(raw.get("matches", 0)))
	for group in ["combos", "units", "structures"]:
		if raw.get(group) is Dictionary:
			for key in raw[group]:
				var entry = raw[group][key]
				if entry is Dictionary and clean[group].size() < MAX_COMBOS:
					var games := maxi(0, int(entry.get("games", 0)))
					clean[group][String(key)] = {"games": games, "wins": clampi(int(entry.get("wins", 0)), 0, games), "draws": clampi(int(entry.get("draws", 0)), 0, games)}
	return clean

static func deck_key(units: Array) -> String:
	var sorted: Array = units.duplicate()
	sorted.sort()
	return ",".join(PackedStringArray(sorted))

## Results are 0 = win, 1 = loss, 2 = draw from the point of view of the given decks.
func record(source: String, units: Array, structures: Array, result: int) -> bool:
	if not SOURCES.has(source) or result < 0 or result > 2 or not Protocol.validate_deck_payload(units, structures):
		return false
	var section: Dictionary = data[source]
	var key := deck_key(units)
	if not section.combos.has(key) and section.combos.size() >= MAX_COMBOS:
		return false
	_bump(section.combos, key, result)
	for kind in units:
		_bump(section.units, String(kind), result)
	for kind in structures:
		_bump(section.structures, String(kind), result)
	section.matches += 1
	dirty = true
	return true

static func _bump(group: Dictionary, key: String, result: int) -> void:
	var entry: Dictionary = group.get(key, {"games": 0, "wins": 0, "draws": 0})
	entry.games += 1
	entry.wins += 1 if result == 0 else 0
	entry.draws += 1 if result == 2 else 0
	group[key] = entry

## Counts a finished server-simulated match once for each side.
func record_model(model: BattleModel) -> void:
	if model.winner == -1:
		return
	for side in 2:
		var result := 2 if model.winner == 2 else (0 if model.winner == side else 1)
		record("online", model.unit_decks[side], model.structure_decks[side], result)
	flush()

## Lower bound of the 95% Wilson interval: a small lucky sample cannot outrank a big solid one.
static func wilson_lower(wins: int, games: int) -> float:
	if games <= 0:
		return 0.0
	var z := 1.96
	var p := float(wins) / float(games)
	var denominator := 1.0 + z * z / float(games)
	var centre := p + z * z / (2.0 * float(games))
	var spread := z * sqrt((p * (1.0 - p) + z * z / (4.0 * float(games))) / float(games))
	return maxf(0.0, (centre - spread) / denominator)

static func _row(key: String, entry: Dictionary) -> Dictionary:
	return {"deck": Array(key.split(",")), "games": int(entry.games), "wins": int(entry.wins), "draws": int(entry.draws),
		"score": snappedf(wilson_lower(int(entry.wins), int(entry.games)), 0.0001)}

## What a client receives: the best well-sampled decks, per-kind pick/win counts and an exact lookup
## for the decks it asked about (even when their sample is small; the client shows the sample size).
func snapshot(decks: Array = []) -> Dictionary:
	var result := {"ruleset": ruleset, "min_samples": MIN_SAMPLES}
	for source in SOURCES:
		var section: Dictionary = data[source]
		var top: Array = []
		for key in section.combos:
			if int(section.combos[key].games) >= MIN_SAMPLES:
				top.append(_row(String(key), section.combos[key]))
		top.sort_custom(func(a, b): return float(a.score) > float(b.score))
		var lookup := {}
		for deck in decks.slice(0, MAX_LOOKUP):
			if deck is Array:
				var key := deck_key(deck)
				if section.combos.has(key):
					lookup[key] = _row(key, section.combos[key])
		result[source] = {"matches": int(section.matches), "top": top.slice(0, TOP_COMBOS), "lookup": lookup,
			"units": section.units.duplicate(true), "structures": section.structures.duplicate(true)}
	return result

func flush(force: bool = false) -> void:
	if path.is_empty() or not dirty:
		return
	var now := Time.get_ticks_msec()
	if not force and last_save_msec != 0 and now - last_save_msec < SAVE_INTERVAL_MSEC:
		return
	last_save_msec = now
	if write_json(path, data):
		dirty = false

static func read_json(file_path: String) -> Variant:
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		return null
	var file := FileAccess.open(file_path, FileAccess.READ)
	return null if file == null else JSON.parse_string(file.get_as_text())

## Writes next to the target and renames, so a crash never leaves a half-written file.
static func write_json(file_path: String, value: Variant) -> bool:
	var temp := file_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value))
	file.close()
	return DirAccess.rename_absolute(temp, file_path) == OK
