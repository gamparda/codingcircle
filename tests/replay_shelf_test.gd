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
	var writer = preload("res://scripts/ServerStats.gd")
	writer.write_json(blocked_path.path_join("ABC234.json"), {"text": "garbage", "public": true, "summary": {}})
	writer.write_json(blocked_path.path_join("ABC235.json"), {"text": text, "public": "false", "summary": {}})
	var raw: Dictionary = writer.read_json(stored_path)
	raw.summary = {"winner": {}, "units": []}
	writer.write_json(stored_path, raw)
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
