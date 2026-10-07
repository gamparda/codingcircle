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
	# Stepwise playback (what a viewer uses) matches run_to_end.
	var player := BattleReplay.Player.new(base)
	var guard := 0
	while player.step() and guard < BattleReplay.MAX_TICKS:
		guard += 1
	check(player.summary().state_hash == base.result.state_hash, "stepwise playback matches")
	# Save / load.
	var path := BattleReplay.save(base, "unit-test")
	check(path != "" and not BattleReplay.load_file(path).is_empty(), "saved replay loads back")
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
	for saved in hooks.saved_paths:
		var loaded := BattleReplay.load_file(saved)
		check(not loaded.is_empty() and bool(BattleReplay.verify(loaded).ok), "server-saved replay verifies")
		DirAccess.remove_absolute(saved)
	print("replay_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
