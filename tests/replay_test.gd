extends SceneTree

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const PLAYER_UNITS := ["shield", "swordsman", "archer"]
const ENEMY_UNITS := ["berserker", "warlock", "necromancer"]
const STEP := 1.0 / float(BattleReplay.DEFAULT_HZ)
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _scripted_battle(with_ai: bool, forced_end: bool) -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, PLAYER_UNITS, ["wall", "swamp", "turret"])
	model.configure_deck(1, ENEMY_UNITS, ["wall", "turret", "generator"])
	var ai: ServerAI = null
	var ai_info := {}
	if with_ai:
		ai = ServerAI.new(1, 4)
		ai_info = {"side": 1, "stage": 4}
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, ai_info, {"mode": "test"})
	var tick := 0
	while model.winner == -1 and tick < 30 * 600:
		var own_kind: String = PLAYER_UNITS[(tick / 45) % 3]
		if tick % 45 == 0 and model.spawn_unit(0, own_kind):
			recorder.on_spawn(0, own_kind)
		if tick == 60 and model.place_structure(0, "wall", 400.0 + sqrt(2.0) * 13.0):
			recorder.on_place(0, "wall", 400.0 + sqrt(2.0) * 13.0)
		var enemy_kind: String = ENEMY_UNITS[(tick / 50) % 3]
		if not with_ai and tick % 50 == 0 and model.spawn_unit(1, enemy_kind):
			recorder.on_spawn(1, enemy_kind)
		if ai != null:
			ai.update(model, STEP)
		model.tick(STEP)
		recorder.on_tick()
		tick += 1
		if forced_end and tick == 900:
			model.winner = 1
	return recorder.finish(model)

func _clone(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _init() -> void:
	BattleReplay.save_dir = "user://replay_test_%d" % OS.get_process_id()
	for config in [[false, false], [true, false], [false, true]]:
		var replay := _scripted_battle(config[0], config[1])
		var label := "ai=%s forced=%s" % config
		check(BattleReplay.valid(replay), "recorded replay is valid (%s)" % label)
		check(int(replay.result.winner) != -1, "scripted battle finished (%s)" % label)
		check(replay.commands.size() > 5, "commands were recorded (%s)" % label)
		var verdict := BattleReplay.verify(replay)
		check(bool(verdict.ok), "re-simulation reproduces the recorded result (%s): %s" % [label, verdict])
		var round_trip := _clone(replay)
		check(BattleReplay.valid(round_trip) and bool(BattleReplay.verify(round_trip).ok), "JSON round trip stays verifiable (%s)" % label)
		check(replay.forced_end.is_empty() != config[1], "forced end recorded only for surrenders/disconnects (%s)" % label)
	# Tampering is detected: changing a command changes the outcome hash.
	var base := _scripted_battle(false, false)
	var tampered := _clone(base)
	tampered.commands.remove_at(2)
	check(not bool(BattleReplay.verify(tampered).ok), "removing a command breaks verification")
	# Untrusted files are rejected rather than simulated.
	var bad := _clone(base)
	bad.commands[0].k = "dragon"
	check(not BattleReplay.valid(bad), "unknown unit kind is rejected")
	bad = _clone(base)
	bad.hz = 0
	check(not BattleReplay.valid(bad), "zero tick rate is rejected")
	bad = _clone(base)
	bad.setup.unit_decks[0] = ["shield", "shield", "archer"]
	check(not BattleReplay.valid(bad), "invalid deck is rejected")
	bad = _clone(base)
	bad.commands[3].t = 0
	check(not BattleReplay.valid(bad), "decreasing command ticks are rejected")
	check(not BattleReplay.valid({}) and not BattleReplay.valid("x"), "garbage is rejected")
	# No conversion errors or silent truncation at the file/share boundary.
	for field in ["format", "hz"]:
		for value in [null, {}, [], true, "30", 30.5, INF, NAN, 1e30]:
			bad = _clone(base)
			bad[field] = value
			check(not BattleReplay.valid(bad), "rejects malformed %s: %s" % [field, value])
	for value in [null, {}, [], "bad", {"winner": 0}, {"ticks": -1, "winner": 0, "elapsed": 1.0, "state_hash": "x"}]:
		bad = _clone(base)
		bad.result = value
		check(not BattleReplay.valid(bad), "rejects incomplete results: %s" % [value])
	for value in [null, [], "bad", {"mode": []}, {"stage": {}}, {"date": 10}]:
		bad = _clone(base)
		bad.meta = value
		check(not BattleReplay.valid(bad), "rejects unsafe display metadata: %s" % [value])
	for field in ["t", "s", "c"]:
		bad = _clone(base)
		bad.commands[0][field] = 0.5 if field != "c" else {}
		check(not BattleReplay.valid(bad), "rejects fractional or non-string commands: %s" % field)
	bad = _clone(base)
	bad.commands[0].t = int(base.result.ticks) + 1
	check(not BattleReplay.valid(bad), "commands cannot extend beyond the recorded result")
	bad = _clone(base)
	bad.setup.unit_decks[0][0] = {}
	check(not BattleReplay.valid(bad), "non-string deck kinds are rejected without conversion")
	for ending in [{"t": -1, "winner": 0}, {"t": int(base.result.ticks) + 1, "winner": 0}, {"t": 1.5, "winner": 0}, {"t": 1, "winner": -1}]:
		bad = _clone(base)
		bad.forced_end = ending
		check(not BattleReplay.valid(bad), "rejects invalid forced endings: %s" % [ending])
	bad = _clone(base)
	bad.meta = []
	check(BattleReplay.from_share_text(BattleReplay.to_share_text(bad)).is_empty(), "invalid shared metadata never reaches the UI")
	# Stepwise playback (what a viewer uses) matches run_to_end.
	var player := BattleReplay.Player.new(base)
	var guard := 0
	while player.step() and guard < BattleReplay.MAX_TICKS:
		guard += 1
	check(player.summary().state_hash == base.result.state_hash, "stepwise playback matches")
	# Exercise the recording boundaries without simulating a two-hour battle.
	var boundary_model := BattleModel.new()
	var boundary_recorder := BattleReplay.Recorder.new(boundary_model)
	boundary_recorder.ticks = BattleReplay.MAX_TICKS
	boundary_model.winner = 0
	var boundary := boundary_recorder.finish(boundary_model)
	check(BattleReplay.valid(boundary), "a forced ending at the final supported tick is valid")
	var boundary_player := BattleReplay.Player.new(boundary)
	boundary_player.ticks = BattleReplay.MAX_TICKS
	check(not boundary_player.step() and boundary_player.model.winner == 0 and boundary_player.ticks == BattleReplay.MAX_TICKS, "playback applies the forced ending at the tick limit without advancing again")
	var too_long := BattleReplay.Recorder.new(boundary_model)
	too_long.ticks = BattleReplay.MAX_TICKS
	too_long.on_tick()
	check(too_long.finish(boundary_model).is_empty() and too_long.finish(boundary_model).is_empty(), "overlong battles never produce a partial replay, including repeat finish calls")
	var full := BattleReplay.Recorder.new(boundary_model)
	for _index in BattleReplay.MAX_COMMANDS:
		full.on_spawn(0, "shield")
	check(BattleReplay.valid(full.finish(boundary_model)), "exactly the supported number of commands can be recorded")
	var overflow := BattleReplay.Recorder.new(boundary_model)
	overflow.replay.commands = full.replay.commands.duplicate()
	overflow.on_spawn(0, "shield")
	check(overflow.finish(boundary_model).is_empty(), "a command beyond the limit invalidates recording rather than silently truncating it")
	# Share text round trip and rejection of anything else.
	var shared := BattleReplay.to_share_text(base)
	check(shared.begins_with(BattleReplay.SHARE_PREFIX) and not shared.contains(" ") and shared.length() < JSON.stringify(base).length(), "share text is one compact line")
	var restored := BattleReplay.from_share_text("  " + shared + "
")
	check(not restored.is_empty() and bool(BattleReplay.verify(restored).ok), "share text imports and still verifies")
	check(BattleReplay.from_share_text("hello").is_empty() and BattleReplay.from_share_text(BattleReplay.SHARE_PREFIX + "###:5").is_empty(), "malformed share text is rejected")
	var broken := shared.substr(0, shared.length() - 12) + ":" + str(JSON.stringify(base).length())
	check(BattleReplay.from_share_text(broken).is_empty(), "corrupted payload is rejected")
	check(BattleReplay.from_share_text(BattleReplay.SHARE_PREFIX + "AAAA:999999999").is_empty(), "absurd decompressed size is rejected")
	# Save / load.
	var path := BattleReplay.save(base, "unit-test")
	check(path != "" and not BattleReplay.load_file(path).is_empty(), "saved replay loads back")
	var duplicate_paths := []
	for _index in 3:
		var another := BattleReplay.save(base, "unit-test")
		check(another != "" and another != path and not duplicate_paths.has(another), "rapid saves never overwrite one another")
		duplicate_paths.append(another)
		DirAccess.remove_absolute(another)
	var original := FileAccess.get_file_as_string(path)
	var noted := BattleReplay.with_note(base, 0, "저장 확인")
	DirAccess.make_dir_absolute(path + ".tmp")
	check(not BattleReplay.write_file(path, noted) and FileAccess.get_file_as_string(path) == original, "failed note save preserves the original replay")
	DirAccess.remove_absolute(path + ".tmp")
	check(BattleReplay.write_file(path, noted) and BattleReplay.load_file(path).notes.size() == 1, "notes save after retry")
	check(not FileAccess.file_exists(path + ".tmp"), "atomic replacement leaves no staging file")
	check(BattleReplay.save(bad, "invalid") == "", "invalid data is not stored")
	if path != "":
		DirAccess.remove_absolute(path)
	# Old damaged files must not take the slots reserved for readable battles.
	var damaged_path := BattleReplay.save_dir.path_join("000_damaged.json")
	var damaged_file := FileAccess.open(damaged_path, FileAccess.WRITE)
	damaged_file.store_string("{broken original")
	damaged_file.close()
	var prune_model := BattleModel.new()
	prune_model.winner = 0
	var short_replay := BattleReplay.Recorder.new(prune_model).finish(prune_model)
	for index in BattleReplay.MAX_SAVED:
		check(BattleReplay.write_file(BattleReplay.save_dir.path_join("90000000_%02d.json" % index), short_replay), "retention fixture written")
	# On Windows an open file prevents removal, reproducing cleanup failure without mocks.
	var oldest := BattleReplay.save_dir.path_join("90000000_00.json")
	var locked: FileAccess = FileAccess.open(oldest, FileAccess.READ) if OS.get_name() == "Windows" else null
	var newest := BattleReplay.save(short_replay, "clock-change")
	check(not newest.is_empty() and FileAccess.file_exists(newest), "save never prunes its own file even when other filenames sort later")
	check(FileAccess.get_file_as_string(damaged_path) == "{broken original", "automatic cleanup preserves unreadable originals")
	var retention := BattleReplay._prune()
	if locked != null:
		check(retention.failed == [oldest] and retention.remaining == BattleReplay.MAX_SAVED + 1, "cleanup reports a real locked file and the actual readable count")
		locked.close()
	retention = BattleReplay._prune()
	check(retention.failed.is_empty() and retention.remaining == BattleReplay.MAX_SAVED and retention.unreadable == 1, "cleanup retry restores the readable limit and leaves damaged data available")
	check(FileAccess.file_exists(newest), "background and manual cleanup retries also preserve the latest save after a clock change")
	for fixture in BattleReplay.list_saved():
		DirAccess.remove_absolute(fixture)
	# Persisted order survives renamed files, repeated clock reversals and process state loss.
	var legacy := BattleReplay.save_dir.path_join("99999999_legacy.json")
	BattleReplay.write_file(legacy, short_replay)
	var first := BattleReplay.save(short_replay, "first")
	var first_renamed := BattleReplay.save_dir.path_join("19000101_first.json")
	DirAccess.rename_absolute(first, first_renamed)
	BattleReplay._last_saved_path = ""
	var second := BattleReplay.save(short_replay, "second")
	var second_renamed := BattleReplay.save_dir.path_join("18000101_second.json")
	DirAccess.rename_absolute(second, second_renamed)
	BattleReplay._last_saved_path = ""
	check(BattleReplay.list_saved() == [second_renamed, first_renamed, legacy], "committed local order survives filename reversal and restart state loss")
	var first_order := int(BattleReplay.load_file(first_renamed)._local_order)
	var edit := BattleReplay.with_note(short_replay, 0, "오래된 기록 편집")
	edit["_local_order"] = 999
	check(BattleReplay.write_file(first_renamed, edit) and int(BattleReplay.load_file(first_renamed)._local_order) == first_order, "notes preserve the stored order even when the editor supplies a different one")
	check(BattleReplay.list_saved()[0] == second_renamed and BattleReplay.list_saved()[1] == first_renamed, "editing an older replay does not promote it in the list")
	var local_second := BattleReplay.load_file(second_renamed)
	check(BattleReplay.to_share_text(local_second) == BattleReplay.to_share_text(_clone(short_replay)), "local retention metadata does not change shared replay identity after a JSON round trip")
	var foreign := short_replay.duplicate(true)
	foreign["_local_order"] = 9007199254740991
	var raw := JSON.stringify(foreign).to_utf8_buffer()
	var foreign_text := BattleReplay.SHARE_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE)) + ":" + str(raw.size())
	check(not BattleReplay.from_share_text(foreign_text).has("_local_order"), "incoming shares cannot inject a foreign local order")
	# Fill to 51 readable files, then retry cleanup with no remembered last save.
	for index in range(3, BattleReplay.MAX_SAVED + 1):
		var fixture := short_replay.duplicate(true)
		fixture["_local_order"] = index
		BattleReplay.write_file(BattleReplay.save_dir.path_join("17000101_%02d.json" % index), fixture)
	retention = BattleReplay._prune()
	check(retention.remaining == BattleReplay.MAX_SAVED and not FileAccess.file_exists(legacy) and FileAccess.file_exists(first_renamed) and FileAccess.file_exists(second_renamed), "restart cleanup trims legacy files before newer committed saves")
	var imported := BattleReplay.save(foreign, "imported")
	check(int(BattleReplay.load_file(imported)._local_order) == BattleReplay.MAX_SAVED + 1 and not foreign.is_empty() and int(foreign._local_order) == 9007199254740991, "saving an imported replay assigns this library's next order without mutating its source")
	BattleReplay._last_saved_path = ""
	BattleReplay._prune()
	check(BattleReplay.list_saved()[0] == imported and not FileAccess.file_exists(first_renamed) and FileAccess.file_exists(second_renamed), "later cleanup removes the actual oldest managed save rather than the smallest filename")
	for value in ["99", -1, 1.5, [99]]:
		var fallback := short_replay.duplicate(true)
		fallback["_local_order"] = value
		check(BattleReplay._storage_order(fallback) == 0 and BattleReplay.valid(fallback), "bad optional local metadata falls back without rejecting the battle")
	for fixture in BattleReplay.list_saved():
		DirAccess.remove_absolute(fixture)
	# Server hooks: record accepted commands only, save once at the end, and replay exactly.
	var Replays = load("res://scripts/ServerReplays.gd")
	var hooks = Replays.new()
	var live := BattleModel.new()
	live.configure_deck(0, PLAYER_UNITS, ["wall", "swamp", "turret"])
	live.configure_deck(1, ENEMY_UNITS, ["wall", "turret", "generator"])
	hooks.begin(7, live, {"mode": "test"})
	for tick in 30 * 900:
		if tick % 40 == 0:
			if live.spawn_unit(0, "swordsman"): hooks.on_spawn(7, 0, "swordsman")
			if live.spawn_unit(1, "berserker"): hooks.on_spawn(7, 1, "berserker")
		if live.winner == -1:
			live.tick(STEP)
			hooks.on_tick(7)
		hooks.settle(7, live)
		if live.winner != -1:
			break
	check(live.winner != -1 and hooks.saved_paths.size() == 1, "server hooks saved exactly one replay: %s" % [hooks.saved_paths])
	hooks.settle(7, live)
	check(hooks.saved_paths.size() == 1, "settling again does not save a duplicate")
	hooks.begin(8, live, {"mode": "test"})
	hooks.recorders[8].ticks = BattleReplay.MAX_TICKS
	hooks.on_tick(8)
	hooks.settle(8, live)
	check(not hooks.recorders.has(8) and hooks.saved_paths.size() == 1, "server discards an over-limit recording without saving a misleading replay")
	# Each persistence destination recovers independently, after its live match is gone.
	var archive_dir := BattleReplay.save_dir
	BattleReplay.save_dir = archive_dir + "/blocked"
	var blocker := FileAccess.open(BattleReplay.save_dir, FileAccess.WRITE)
	blocker.store_string("blocked archive")
	blocker.close()
	var retry_hooks = Replays.new()
	var Shelf = preload("res://scripts/ServerReplayShelf.gd")
	var Stats = preload("res://scripts/ServerStats.gd")
	retry_hooks.shelf = Shelf.new()
	var shelf_root := archive_dir + "/shelf"
	retry_hooks.shelf.configure(shelf_root)
	retry_hooks.stats = Stats.new()
	# Archive fails, shared copy succeeds. Retrying must not duplicate the public copy.
	var failed_model := BattleModel.new()
	retry_hooks.begin(91, failed_model, {"mode": "room"})
	failed_model.tick(STEP)
	retry_hooks.on_tick(91)
	failed_model.winner = 0
	retry_hooks.settle(91, failed_model)
	check(retry_hooks.pending.size() == 1 and retry_hooks.pending[0].shared and retry_hooks.shelf.recent().size() == 1, "failed archive is retained while its shared copy is available")
	retry_hooks.drop(91)
	retry_hooks.settle(91, failed_model)
	retry_hooks.retry_pending()
	check(retry_hooks.pending.size() == 1 and retry_hooks.stats.data.online.matches == 2, "dropping, settling and failed retries preserve the record without recounting results")
	DirAccess.remove_absolute(BattleReplay.save_dir)
	retry_hooks.retry_pending()
	check(retry_hooks.pending.is_empty() and retry_hooks.saved_paths.size() == 1 and retry_hooks.shelf.recent().size() == 1, "archive retry saves once without duplicating the shared copy")
	# Archive succeeds, public shelf fails. Retry cannot produce a second archive.
	var shelf_backup: String = retry_hooks.shelf.dir + ".backup"
	DirAccess.rename_absolute(retry_hooks.shelf.dir, shelf_backup)
	blocker = FileAccess.open(retry_hooks.shelf.dir, FileAccess.WRITE)
	blocker.store_string("blocked shelf")
	blocker.close()
	failed_model = BattleModel.new()
	retry_hooks.begin(92, failed_model, {"mode": "rematch"})
	for _tick in 2:
		failed_model.tick(STEP)
		retry_hooks.on_tick(92)
	failed_model.winner = 1
	retry_hooks.settle(92, failed_model)
	check(retry_hooks.pending.size() == 1 and retry_hooks.pending[0].archived and retry_hooks.saved_paths.size() == 2, "failed sharing retains its replay after a successful archive")
	DirAccess.remove_absolute(retry_hooks.shelf.dir)
	DirAccess.rename_absolute(shelf_backup, retry_hooks.shelf.dir)
	retry_hooks.retry_pending()
	retry_hooks.retry_pending()
	check(retry_hooks.pending.is_empty() and retry_hooks.saved_paths.size() == 2 and retry_hooks.shelf.recent().size() == 2 and retry_hooks.stats.data.online.matches == 4, "share retry publishes once without duplicating archives or statistics")
	for saved in retry_hooks.saved_paths:
		check(bool(BattleReplay.verify(BattleReplay.load_file(saved)).ok), "recovered server replay verifies")
		DirAccess.remove_absolute(saved)
	for file in DirAccess.get_files_at(retry_hooks.shelf.dir):
		DirAccess.remove_absolute(retry_hooks.shelf.dir.path_join(file))
	DirAccess.remove_absolute(retry_hooks.shelf.dir)
	DirAccess.remove_absolute(shelf_root)
	DirAccess.remove_absolute(BattleReplay.save_dir)
	BattleReplay.save_dir = archive_dir
	# Long-running servers retain only recent diagnostic paths, independent of retry state.
	var history = Replays.new()
	for index in BattleReplay.MAX_SAVED:
		history.saved_paths.append("old_%d.json" % index)
	history.begin(93, failed_model, {"mode": "test"})
	history.settle(93, failed_model)
	var latest_path: String = history.saved_paths[-1]
	check(history.saved_paths.size() == BattleReplay.MAX_SAVED and history.saved_paths[0] == "old_1.json" and FileAccess.file_exists(latest_path) and history.pending.is_empty(), "a successful archive bounds path history while retaining the actual new file")
	history.settle(93, failed_model)
	history.retry_pending()
	check(history.saved_paths.size() == BattleReplay.MAX_SAVED and history.saved_paths[-1] == latest_path, "settle and retry never duplicate the diagnostic history")
	DirAccess.remove_absolute(latest_path)
	for saved in hooks.saved_paths:
		var loaded := BattleReplay.load_file(saved)
		check(not loaded.is_empty() and bool(BattleReplay.verify(loaded).ok), "server-saved replay verifies")
		DirAccess.remove_absolute(saved)
	DirAccess.remove_absolute(BattleReplay.save_dir)
	print("replay_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
