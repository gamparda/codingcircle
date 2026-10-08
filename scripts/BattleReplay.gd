extends RefCounted
## Command-log replays. Combat is deterministic (no RNG, fixed step), so a replay only
## stores the initial setup plus the accepted player commands; playback re-simulates the
## battle with the real BattleModel. This keeps files tiny and doubles as a regression
## tool: if re-simulating a replay no longer reproduces its recorded result hash, the
## rules changed since it was recorded.

const FORMAT := 1
const DEFAULT_HZ := 30
const MAX_COMMANDS := 20000
const MAX_TICKS := 30 * 3600 * 2
## Where replays live; tests point this at a scratch folder so they never touch real replays.
static var save_dir := "user://replays"
const MAX_SAVED := 50

# --- recording ---------------------------------------------------------------

class Recorder extends RefCounted:
	var replay: Dictionary = {}
	var ticks := 0
	var finished := false

	func _init(model: BattleModel, hz: int = 30, ai: Dictionary = {}, meta: Dictionary = {}) -> void:
		replay = {
			"format": 1, "hz": hz, "meta": meta.duplicate(true),
			"setup": {
				"unit_decks": model.unit_decks.duplicate(true), "structure_decks": model.structure_decks.duplicate(true),
				"campaign_levels": model.campaign_levels.duplicate(), "base_max_hp": model.base_max_hp.duplicate(),
				"base_hp": model.base_hp.duplicate(), "resources": model.resources.duplicate(),
			},
			"ai": ai.duplicate(), "commands": [], "forced_end": {}, "result": {},
		}

	## Call after every executed model.tick().
	func on_tick() -> void:
		ticks += 1

	func on_spawn(side: int, kind: String) -> void:
		_command({"t": ticks, "s": side, "c": "spawn", "k": kind})

	func on_place(side: int, kind: String, x: float) -> void:
		_command({"t": ticks, "s": side, "c": "place", "k": kind, "x": x})

	func _command(entry: Dictionary) -> void:
		if not finished and replay.commands.size() < 20000:
			replay.commands.append(entry)

	## Seals the replay. `model` must be in its final state.
	func finish(model: BattleModel) -> Dictionary:
		if finished:
			return replay
		finished = true
		var natural: bool = model.base_hp[0] <= 0.0 or model.base_hp[1] <= 0.0
		if model.winner != -1 and not natural:
			replay.forced_end = {"t": ticks, "winner": model.winner}
		replay.result = {"winner": model.winner, "ticks": ticks, "elapsed": model.elapsed, "state_hash": model.state_hash()}
		return replay

# --- helpers -----------------------------------------------------------------

static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func valid(replay: Variant) -> bool:
	if not replay is Dictionary or int(replay.get("format", 0)) != FORMAT:
		return false
	for key in ["hz", "setup", "commands", "result"]:
		if not replay.has(key):
			return false
	if not replay.hz is int and not (replay.hz is float and replay.hz == floorf(replay.hz)) or int(replay.hz) < 10 or int(replay.hz) > 120:
		return false
	var setup = replay.setup
	if not setup is Dictionary:
		return false
	for key in ["unit_decks", "structure_decks", "campaign_levels", "base_max_hp", "base_hp", "resources"]:
		if not setup.has(key) or not setup[key] is Array or setup[key].size() != 2:
			return false
	for side in 2:
		if not setup.unit_decks[side] is Array or not BattleModel._valid_deck(setup.unit_decks[side], BattleModel.UNIT_STATS):
			return false
		if not setup.structure_decks[side] is Array or not BattleModel._valid_deck(setup.structure_decks[side], BattleModel.STRUCTURE_STATS):
			return false
		for key in ["campaign_levels", "base_max_hp", "base_hp", "resources"]:
			var value = setup[key][side]
			if not _is_number(value) or float(value) < 0.0 or float(value) > 100000.0:
				return false
	if not replay.commands is Array or replay.commands.size() > MAX_COMMANDS:
		return false
	var last_tick := 0
	for entry in replay.commands:
		if not entry is Dictionary or not entry.has_all(["t", "s", "c", "k"]):
			return false
		if not _is_number(entry.t) or int(entry.t) < last_tick or int(entry.t) > MAX_TICKS:
			return false
		last_tick = int(entry.t)
		if not _is_number(entry.s) or int(entry.s) < 0 or int(entry.s) > 1 or not entry.k is String:
			return false
		match String(entry.c):
			"spawn":
				if not BattleModel.UNIT_STATS.has(entry.k):
					return false
			"place":
				if not BattleModel.STRUCTURE_STATS.has(entry.k) or not _is_number(entry.get("x")):
					return false
			_:
				return false
	var ai = replay.get("ai", {})
	if not ai is Dictionary:
		return false
	if not ai.is_empty() and (not _is_number(ai.get("side")) or int(ai.side) not in [0, 1] or not _is_number(ai.get("stage")) or int(ai.stage) < 1 or int(ai.stage) > 8):
		return false
	var forced = replay.get("forced_end", {})
	if not forced is Dictionary or (not forced.is_empty() and (not _is_number(forced.get("t")) or not _is_number(forced.get("winner")) or int(forced.winner) < -1 or int(forced.winner) > 2)):
		return false
	if replay.has("clip"):
		var clip = replay.clip
		if not clip is Dictionary or not _is_number(clip.get("start")) or not _is_number(clip.get("end")):
			return false
		if int(clip.start) < 0 or int(clip.end) <= int(clip.start) or int(clip.end) > MAX_TICKS or String(clip.get("title", "")).length() > 80:
			return false
	if replay.has("notes") and not _valid_notes(replay.notes, replay.result):
		return false
	return replay.result is Dictionary

# --- playback ----------------------------------------------------------------

class Player extends RefCounted:
	var replay: Dictionary
	var model: BattleModel
	var ai: ServerAI = null
	var ticks := 0
	var cursor := 0
	var dt := 1.0 / 30.0

	func _init(source: Dictionary) -> void:
		replay = source
		dt = 1.0 / float(int(source.hz))
		model = BattleModel.new()
		var setup: Dictionary = source.setup
		for side in 2:
			model.configure_deck(side, setup.unit_decks[side], setup.structure_decks[side])
			model.campaign_levels[side] = int(setup.campaign_levels[side])
			model.base_max_hp[side] = float(setup.base_max_hp[side])
			model.base_hp[side] = float(setup.base_hp[side])
			model.resources[side] = float(setup.resources[side])
		var ai_info: Dictionary = source.get("ai", {})
		if not ai_info.is_empty():
			ai = ServerAI.new(int(ai_info.side), int(ai_info.stage))

	func is_finished() -> bool:
		return model.winner != -1

	## Re-simulates one tick; returns false once the battle is over.
	func step() -> bool:
		if model.winner != -1 or ticks >= 30 * 3600 * 2:
			return false
		var commands: Array = replay.commands
		while cursor < commands.size() and int(commands[cursor].t) <= ticks:
			var entry: Dictionary = commands[cursor]
			if String(entry.c) == "spawn":
				model.spawn_unit(int(entry.s), String(entry.k))
			else:
				model.place_structure(int(entry.s), String(entry.k), float(entry.x))
			cursor += 1
		var forced: Dictionary = replay.get("forced_end", {})
		if not forced.is_empty() and ticks >= int(forced.t):
			model.winner = int(forced.winner)
			return false
		if ai != null:
			ai.update(model, dt)
		model.tick(dt)
		ticks += 1
		return model.winner == -1

	func run_to_end() -> Dictionary:
		while step():
			pass
		return summary()

	func summary() -> Dictionary:
		return {"winner": model.winner, "ticks": ticks, "elapsed": model.elapsed, "state_hash": model.state_hash()}

static func verify(replay: Dictionary) -> Dictionary:
	if not valid(replay):
		return {"ok": false, "error": "invalid replay"}
	var played := Player.new(replay).run_to_end()
	var recorded: Dictionary = replay.result
	var matches: bool = String(played.state_hash) == String(recorded.get("state_hash", "")) and int(played.winner) == int(recorded.get("winner", -2))
	return {"ok": matches, "played": played, "recorded": recorded}

# --- clips -------------------------------------------------------------------
## A clip is the whole replay plus a window. The viewer starts at `start` and pauses at `end`, so sharing
## a 20-second moment costs no more than sharing the replay (and still verifies like any other).
static func make_clip(replay: Dictionary, center_tick: int, title: String, before: int = 300, after: int = 300) -> Dictionary:
	var total := int(replay.get("result", {}).get("ticks", 0))
	var clip: Dictionary = replay.duplicate(true)
	var start := clampi(center_tick - before, 0, maxi(0, total - 1))
	var end := clampi(center_tick + after, start + 1, maxi(start + 1, total))
	clip["clip"] = {"start": start, "end": end, "title": title.left(80)}
	return clip

# --- notes -------------------------------------------------------------------
## Short remarks pinned to a moment ("여기서 방벽을 깔았어야 함"). Pure metadata: the simulation never reads them,
## so they do not affect verification, and they travel with the replay file and its share text.
const MAX_NOTES := 20
const MAX_NOTE_LENGTH := 40

static func _valid_notes(notes: Variant, result: Variant) -> bool:
	if not notes is Array or notes.size() > MAX_NOTES:
		return false
	var limit := MAX_TICKS
	if result is Dictionary and _is_number(result.get("ticks")):
		limit = mini(limit, int(result.ticks))
	var seen := {}
	for note in notes:
		if not note is Dictionary or not _is_number(note.get("t")) or not note.get("text") is String:
			return false
		var text: String = note.text
		if int(note.t) < 0 or int(note.t) > limit or seen.has(int(note.t)) or text.strip_edges().is_empty() or text.length() > MAX_NOTE_LENGTH:
			return false
		for index in text.length():
			if text.unicode_at(index) < 32 or text.unicode_at(index) == 127:
				return false
		seen[int(note.t)] = true
	return true

static func notes_of(replay: Dictionary) -> Array:
	return replay.get("notes", []) if replay.get("notes") is Array else []

## Returns a copy with the note added (replacing one on the same tick). A full list or bad text returns the original.
static func with_note(replay: Dictionary, tick: int, text: String) -> Dictionary:
	var clean := text.strip_edges().left(MAX_NOTE_LENGTH)
	var notes: Array = notes_of(replay).duplicate(true)
	notes = notes.filter(func(note): return int(note.t) != tick)
	notes.append({"t": tick, "text": clean})
	notes.sort_custom(func(a, b): return int(a.t) < int(b.t))
	if clean.is_empty() or not _valid_notes(notes, replay.get("result", {})):
		return replay
	var copy: Dictionary = replay.duplicate(true)
	copy["notes"] = notes
	return copy

static func without_note(replay: Dictionary, tick: int) -> Dictionary:
	var copy: Dictionary = replay.duplicate(true)
	var notes: Array = notes_of(copy).filter(func(note): return int(note.t) != tick)
	if notes.is_empty():
		copy.erase("notes")
	else:
		copy["notes"] = notes
	return copy

## The note closest to `tick` within `tolerance` ticks, or {}.
static func nearest_note(replay: Dictionary, tick: int, tolerance: int = 90) -> Dictionary:
	var best := {}
	var best_distance := tolerance + 1
	for note in notes_of(replay):
		var distance := absi(int(note.t) - tick)
		if distance < best_distance:
			best_distance = distance
			best = note
	return best

static func clip_of(replay: Dictionary) -> Dictionary:
	return replay.get("clip", {}) if replay.get("clip") is Dictionary else {}

# --- sharing -----------------------------------------------------------------
const SHARE_PREFIX := "CATWAR-REPLAY1:"
const MAX_SHARE_CHARS := 2_000_000

## Compact single-line text (deflate + base64) that can be pasted into chat or a bug report.
static func to_share_text(replay: Dictionary) -> String:
	var raw := JSON.stringify(replay).to_utf8_buffer()
	return SHARE_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE)) + ":" + str(raw.size())

## Parses share text back into a validated replay, or {} when it is not a good replay.
static func from_share_text(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	if cleaned.length() > MAX_SHARE_CHARS or not cleaned.begins_with(SHARE_PREFIX):
		return {}
	var parts := cleaned.trim_prefix(SHARE_PREFIX).split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return {}
	var raw_size := int(parts[1])
	if raw_size <= 0 or raw_size > 8 * 1024 * 1024:
		return {}
	var packed := Marshalls.base64_to_raw(parts[0])
	if packed.is_empty():
		return {}
	var raw := packed.decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return {}
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	return parsed if valid(parsed) else {}

# --- storage -----------------------------------------------------------------

static func save(replay: Dictionary, name_hint: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "_")
	var safe := ""
	for ch in name_hint:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "-":
			safe += ch
	var path := "%s/%s%s.json" % [save_dir, stamp, ("_" + safe) if safe != "" else ""]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(replay))
	file.close()
	_prune()
	return path

## Rewrites an existing replay file (used when notes change).
static func write_file(path: String, replay: Dictionary) -> bool:
	if not valid(replay):
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(replay))
	file.close()
	return true

static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 4 * 1024 * 1024:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if valid(parsed) else {}

static func list_saved() -> Array:
	var names: Array = []
	if not DirAccess.dir_exists_absolute(save_dir):
		return names
	for file in DirAccess.get_files_at(save_dir):
		if file.ends_with(".json"):
			names.append(save_dir + "/" + file)
	names.sort()
	names.reverse()
	return names

static func _prune() -> void:
	var names := list_saved()
	for index in range(MAX_SAVED, names.size()):
		DirAccess.remove_absolute(names[index])
