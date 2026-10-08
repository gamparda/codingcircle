extends SceneTree
## Ghost battles (play against a replay's other player) and what-if branches (continue a replay yourself).

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const GhostOpponent = preload("res://scripts/GhostOpponent.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _pvp_replay() -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	model.configure_deck(1, ["berserker", "warlock", "necromancer"], ["wall", "turret", "generator"])
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {}, {"mode": "quick"})
	var tick := 0
	while model.winner == -1 and tick < 30 * 120:
		if tick % 90 == 0 and model.spawn_unit(0, "swordsman"):
			recorder.on_spawn(0, "swordsman")
		if tick % 40 == 0 and model.spawn_unit(1, "berserker"):
			recorder.on_spawn(1, "berserker")
		if tick == 100 and model.place_structure(1, "wall", 1000.0):
			recorder.on_place(1, "wall", 1000.0)
		model.tick(1.0 / 30.0)
		recorder.on_tick()
		tick += 1
	return recorder.finish(model)

func _campaign_replay() -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	model.configure_deck(1, ServerAI.stage_unit_deck(3), ServerAI.stage_structure_deck(3))
	var ai := ServerAI.new(1, 3)
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": 3}, {"mode": "campaign", "stage": 3})
	var tick := 0
	while model.winner == -1 and tick < 30 * 150:
		if tick % 60 == 0 and model.spawn_unit(0, "swordsman"):
			recorder.on_spawn(0, "swordsman")
		ai.update(model, 1.0 / 30.0)
		model.tick(1.0 / 30.0)
		recorder.on_tick()
		tick += 1
	return recorder.finish(model)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var pvp := _pvp_replay()
	var counts := [GhostOpponent.command_count(pvp, 0), GhostOpponent.command_count(pvp, 1)]
	var ghost_side := GhostOpponent.pick_side(pvp)
	check(counts[ghost_side] == maxi(counts[0], counts[1]) and GhostOpponent.playable(pvp), "the busiest side is the ghost: %s -> %d" % [counts, ghost_side])
	var ghost_kind := "swordsman" if ghost_side == 0 else "berserker"
	var campaign := _campaign_replay()
	check(GhostOpponent.pick_side(campaign) == 0, "in a campaign replay the human (blue) is the ghost")
	check(not GhostOpponent.playable({"commands": [{"t": 1, "s": 0, "c": "spawn", "k": "shield"}]}), "a replay with almost no commands is not worth a ghost")

	# GhostOpponent mechanics.
	var script := {"commands": [{"t": 0, "s": 0, "c": "spawn", "k": "swordsman"}, {"t": 5, "s": 0, "c": "place", "k": "wall", "x": 400.0}, {"t": 5, "s": 1, "c": "spawn", "k": "archer"}]}
	var model := BattleModel.new()
	model.resources = [180.0, 180.0]
	model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	model.configure_deck(1, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	var ghost := GhostOpponent.new(script, 0, true)
	check(ghost.commands.size() == 2, "only the ghost side's commands are kept")
	ghost.update(model, 0.0)
	check(model.units.size() == 1 and int(model.units[0].side) == 1, "tick 0 command lands on the red side")
	for i in 5:
		ghost.update(model, 0.0)
	check(model.structures.size() == 1 and absf(float(model.structures[0].x) - (BattleModel.WORLD_WIDTH - 400.0)) < 0.01 and int(model.structures[0].side) == 1, "builds are mirrored onto the red build zone")
	var resumed := GhostOpponent.new(script, 0, false, 5)
	check(resumed.commands.size() == 1 and resumed.ticks == 5, "from_tick skips commands that already happened")

	BattleReplay.save_dir = "user://ghost_battle_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	var matches_before: int = main.save_data.stats.ai_matches

	# Ghost battle.
	main._start_ghost_battle(pvp)
	main.set_process(false)
	check(main.ghost_context.mode == "ghost" and main.local_ai is GhostOpponent and main.local_recorder == null, "ghost battle uses a scripted opponent and records nothing")
	check(main.local_model.unit_decks[0] == pvp.setup.unit_decks[1 - ghost_side] and main.local_model.unit_decks[1] == pvp.setup.unit_decks[ghost_side], "decks come from the replay (mine = the other side's)")
	main.local_model.resources[0] = 180.0
	for i in 60:
		main._process(0.1)
	check(main.local_model.units.any(func(unit): return int(unit.side) == 1 and unit.kind == ghost_kind), "the ghost buys its recorded %ss" % ghost_kind)
	main.local_model.winner = 0
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	check(main.result_overlay.find_child("ResultDetails", true, false) != null, "result screen shows")
	check(main.save_data.stats.ai_matches == matches_before and main.save_data.achievements.has("ghost_buster") and not main.save_data.achievements.has("first_win"), "ghost wins count only for the ghost badge, never for statistics")
	var note_texts: Array = main.result_overlay.find_children("*", "Label", true, false).map(func(label): return label.text)
	check(note_texts.any(func(text): return text.contains("고스트를 이겼습니다")), "result says the ghost was beaten")
	var ticks_before: int = int(main.local_model.elapsed * 30.0)
	var again: Button = main.result_overlay.find_children("*", "Button", true, false).filter(func(button): return button.text == "다시 도전")[0]
	again.pressed.emit()
	await process_frame
	check(main.ghost_context.mode == "ghost" and main.local_model.elapsed < 1.0 and ticks_before > 0, "'다시 도전' restarts the same ghost battle")

	# What-if branch from a campaign replay (red keeps its AI).
	var mid := int(campaign.result.ticks) / 2
	main._start_branch_battle(campaign, mid)
	main.set_process(false)
	check(main.ghost_context.mode == "branch" and main.local_ai is ServerAI and absi(int(main.local_model.elapsed * 30.0) - mid) <= 1, "branch continues from the chosen moment with the recorded AI")
	var blue_units_at_branch: int = main.local_model.units.filter(func(unit): return int(unit.side) == 0).size()
	main._purchase_unit(main.battle_preset.units[0])
	for i in 10:
		main._process(0.1)
	check(main.local_model.units.size() > 0 and main.local_recorder == null, "the human can act in the branch and nothing is recorded")
	main.local_model.winner = 1
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	check(main.save_data.stats.ai_matches == matches_before and main.save_data.stats.win_streak == 0, "branch results never touch statistics or streaks")
	# Finished replays cannot be branched.
	var before_mode: String = main.ghost_context.mode
	main._start_branch_battle(campaign, int(campaign.result.ticks) + 100)
	check(main.ghost_context.mode == before_mode and main.result_shown, "branching a finished moment does nothing")

	# Viewer button and list button.
	var saved := BattleReplay.save(pvp, "ghost-test")
	main._build_replay_list()
	await process_frame
	var ghost_button = main.find_child("GhostReplayButton", true, false)
	check(ghost_button != null, "the replay list offers a ghost challenge")
	main._play_replay(saved)
	await process_frame
	var viewer = main.replay_viewer
	var captured := []
	viewer.branch_requested.connect(func(tick): captured.append(tick))
	viewer.seek(120)
	viewer.find_child("ReplayBranchButton", true, false).pressed.emit()
	check(captured == [120], "the viewer asks to branch from the current moment")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://ghost_battle_test")
	print("ghost_battle_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
