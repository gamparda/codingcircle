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
	for saved in hooks.saved_paths:
		var loaded := BattleReplay.load_file(saved)
		check(not loaded.is_empty() and bool(BattleReplay.verify(loaded).ok), "server-saved replay verifies")
		DirAccess.remove_absolute(saved)
	DirAccess.remove_absolute(BattleReplay.save_dir)
	print("replay_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
