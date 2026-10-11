extends SceneTree
## Server shelf of shared replays: codes, public listing, bounds and persistence.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ServerReplayShelf = preload("res://scripts/ServerReplayShelf.gd")
const Protocol = preload("res://scripts/NetworkProtocol.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _replay(seed_tick: int) -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	model.configure_deck(1, ["berserker", "warlock", "necromancer"], ["wall", "turret", "generator"])
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {}, {"mode": "quick"})
	for tick in 120 + seed_tick:
		if tick % 40 == 0 and model.spawn_unit(0, "swordsman"):
			recorder.on_spawn(0, "swordsman")
		model.tick(1.0 / 30.0)
		recorder.on_tick()
	model.winner = 0
	return recorder.finish(model)

## The shelf keeps its files in a subfolder; remove both levels.
func _clear(dir: String) -> void:
	var shelf_dir := dir.path_join("shared_replays")
	for file in DirAccess.get_files_at(shelf_dir):
		DirAccess.remove_absolute(shelf_dir.path_join(file))
	DirAccess.remove_absolute(shelf_dir)
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var dir := "user://replay_shelf_test"
	DirAccess.make_dir_recursive_absolute(dir)
	_clear(dir)
	var shelf := ServerReplayShelf.new()
	shelf.configure(dir)
	var text := BattleReplay.to_share_text(_replay(0))
	var code := shelf.add(text, false)
	check(Protocol.is_valid_room_code(code), "a replay gets a six-letter code")
	check(shelf.add(text, false) == code and shelf.entries.size() == 1, "the same replay always gets the same code")
	check(shelf.add(" \n" + text + "\n ", false) == code and shelf.entries.size() == 1, "whitespace shares reuse the same code")
	var original_replay := _replay(0)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(original_replay))
	var roundtrip_text := BattleReplay.to_share_text(roundtrip)
	check(shelf.add(roundtrip_text) == code and shelf.entries.size() == 1, "JSON number round trips reuse the original share code")
	var reordered: Dictionary = {}
	var keys: Array = roundtrip.keys()
	keys.reverse()
	for key in keys: reordered[key] = roundtrip[key]
	var raw := JSON.stringify(reordered, "\t", false).to_utf8_buffer()
	var formatted_text := BattleReplay.SHARE_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE)) + ":" + str(raw.size())
	check(shelf.add(formatted_text) == code and shelf.entries.size() == 1, "JSON layout and key order do not create another code")
	var previous_save_dir := BattleReplay.save_dir
	BattleReplay.save_dir = dir.path_join("local")
	var local_path := BattleReplay.save(original_replay)
	check(not local_path.is_empty() and shelf.add(BattleReplay.to_share_text(BattleReplay.load_file(local_path))) == code and shelf.entries.size() == 1, "saving to disk and loading with local order preserves the share code")
	DirAccess.remove_absolute(local_path)
	DirAccess.remove_absolute(BattleReplay.save_dir)
	BattleReplay.save_dir = previous_save_dir
	check(shelf.text_for(code) == text.strip_edges() and shelf.text_for("ZZZZZZ") == "", "the text comes back by code only")
	check(shelf.recent().is_empty(), "private uploads are not listed")
	check(shelf.add(text, true) == code and shelf.recent().size() == 1 and shelf.recent()[0].code == code, "making it public lists it once")
	check(shelf.add("garbage", false) == "" and shelf.add("x".repeat(ServerReplayShelf.MAX_TEXT + 1), false) == "", "garbage and oversized text are refused")
	var second := shelf.add(BattleReplay.to_share_text(_replay(30)), true)
	check(shelf.recent()[0].code == second and shelf.recent()[1].code == code, "recent battles list the newest first")
	check(shelf.recent()[0].units[1] == ["berserker", "warlock", "necromancer"] and int(shelf.recent()[0].winner) == 0, "summaries carry decks and winner")
	var reloaded := ServerReplayShelf.new()
	reloaded.configure(dir)
	check(reloaded.text_for(code) == text.strip_edges() and reloaded.recent().size() == 2, "the shelf survives a restart")
	check(reloaded.recent()[0].code == second, "same-second creation order survives a restart")
	check(reloaded.add(roundtrip_text) == code and reloaded.entries.size() == 2, "normalized content reuses the original code after restart")
	var variants := ServerReplayShelf.new()
	var plain := variants.add(text)
	var note_text := BattleReplay.to_share_text(BattleReplay.with_note(original_replay, 20, "공유 메모"))
	var note_code := variants.add(note_text)
	check(note_code != plain and variants.text_for(note_code) == note_text, "different notes get their own code and are preserved")
	var clip := original_replay.duplicate(true)
	clip.clip = {"start": 10, "end": 100, "title": "명장면"}
	check(variants.add(BattleReplay.to_share_text(clip)) != plain, "a clip stays distinct from the full replay")
	var precise := roundtrip.duplicate(true)
	precise.setup.resources[0] += 0.00000000001
	check(variants.add(BattleReplay.to_share_text(precise)) != plain, "different accepted numerical content is not rounded into the same share")
	# Existing duplicate encodings keep both codes and bytes; reuse the oldest retained one.
	var legacy_dir := dir.path_join("legacy")
	var legacy_path := legacy_dir.path_join("shared_replays")
	var writer = preload("res://scripts/ServerStats.gd")
	writer.write_json(legacy_path.path_join("ABC234.json"), {"text": text, "public": false, "created_usec": 1})
	writer.write_json(legacy_path.path_join("ABC235.json"), {"text": roundtrip_text, "public": true, "created_usec": 2})
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path.path_join("ABC234.json"))
	var legacy := ServerReplayShelf.new()
	legacy.configure(legacy_dir)
	check(legacy.add(formatted_text) == "ABC234" and legacy.entries.size() == 2, "existing equivalent encodings reuse the oldest retained code")
	check(legacy.text_for("ABC234") == text and legacy.text_for("ABC235") == roundtrip_text and legacy.recent().size() == 1, "all legacy codes and public flags remain usable")
	check(FileAccess.get_file_as_bytes(legacy_path.path_join("ABC234.json")) == legacy_bytes, "normalization does not rewrite existing files")
	for index in ServerReplayShelf.MAX_STORED - 1:
		legacy.entries.append({"code": "fixture%d" % index, "text": "fixture", "public": false, "summary": {}, "key": "fixture%d" % index})
	legacy._trim()
	check(legacy.add(text) == "ABC235" and legacy.entries.size() == ServerReplayShelf.MAX_STORED, "pruning a legacy duplicate reuses the remaining code without another upload")
	_clear(legacy_dir)
	# Disk failures must not issue an ephemeral code or publish a failed promotion.
	var blocked_dir := dir.path_join("blocked")
	DirAccess.make_dir_recursive_absolute(blocked_dir)
	var blocked_path := blocked_dir.path_join("shared_replays")
	var blocker := FileAccess.open(blocked_path, FileAccess.WRITE)
	blocker.store_string("blocked")
	blocker.close()
	var failed := ServerReplayShelf.new()
	failed.configure(blocked_dir)
	check(failed.add(text) == "" and failed.entries.is_empty() and failed.by_hash.is_empty(), "failed persistence returns no code and changes no shelf indexes")
	DirAccess.remove_absolute(blocked_path)
	var recovered_code := failed.add(text)
	check(Protocol.is_valid_room_code(recovered_code), "retry recreates the shelf directory and stores the replay")
	var stored_path := blocked_path.path_join(recovered_code + ".json")
	var original := FileAccess.get_file_as_string(stored_path)
	DirAccess.make_dir_absolute(stored_path + ".tmp")
	check(failed.add(text, true) == "" and failed.recent().is_empty() and FileAccess.get_file_as_string(stored_path) == original, "failed promotion preserves the private replay and its disk file")
	DirAccess.remove_absolute(stored_path + ".tmp")
	check(failed.add(text, true) == recovered_code and failed.recent().size() == 1, "promotion can retry with the original code")
	var after_retry := ServerReplayShelf.new()
	after_retry.configure(blocked_dir)
	check(after_retry.text_for(recovered_code) == text and after_retry.recent().size() == 1, "recovered code and public flag survive restart")
	# Load only valid share text, rebuilding display metadata from the replay itself.
	writer.write_json(blocked_path.path_join("ABC234.json"), {"text": "garbage", "public": true, "summary": {}})
	writer.write_json(blocked_path.path_join("ABC235.json"), {"text": text, "public": "false", "summary": {}})
	var stored: Dictionary = writer.read_json(stored_path)
	stored.summary = {"winner": {}, "units": []}
	writer.write_json(stored_path, stored)
	after_retry.configure(blocked_dir)
	check(after_retry.entries.size() == 1 and after_retry.recent()[0].units[1] == ["berserker", "warlock", "necromancer"], "invalid records are excluded and malformed summary metadata is rebuilt")
	_clear(blocked_dir)
	# Bounded: the oldest entries fall off.
	var bounded := ServerReplayShelf.new()
	for i in ServerReplayShelf.MAX_STORED + 5:
		bounded.entries.append({"code": "AAAA%02d" % (i % 100), "public": false, "summary": {}, "text": "t%d" % i})
	bounded._trim()
	check(bounded.entries.size() == ServerReplayShelf.MAX_STORED, "the shelf is bounded")
	# Failed removal must not silently forget a file that reappears at the next restart.
	bounded.dir = dir.path_join("trim")
	var oldest_path: String = bounded.dir.path_join(String(bounded.entries[0].code) + ".json")
	DirAccess.make_dir_recursive_absolute(oldest_path)
	bounded.entries.append({"code": "ABC236", "public": false, "summary": {}, "text": "new"})
	bounded._trim()
	check(bounded.trim_failed and bounded.entries.size() == ServerReplayShelf.MAX_STORED + 1, "failed pruning retains the oldest entry for a later retry")
	check(bounded.add(text) == "" and bounded.entries.size() == ServerReplayShelf.MAX_STORED + 1, "blocked pruning refuses additional growth until deletion can recover")
	DirAccess.remove_absolute(oldest_path)
	bounded._trim()
	check(not bounded.trim_failed and bounded.entries.size() == ServerReplayShelf.MAX_STORED, "pruning retries after the blocked path is repaired")
	DirAccess.remove_absolute(bounded.dir)
	_clear(dir)
	print("replay_shelf_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
