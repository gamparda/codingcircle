extends SceneTree
## Plain practice battles are recorded and replay exactly; practice tools switch recording off.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	BattleReplay.save_dir = "user://practice_replay_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data.tutorial_completed = true
	main.campaign_mode = false
	main._start_local_ai_battle(2)
	check(main.local_recorder != null, "plain practice is recorded")
	main.set_process(false)
	main.local_model.resources[0] = 180.0
	main._purchase_unit(main.battle_preset.units[0])
	for i in 400:
		main._process(0.1)
		if main.local_model.winner != -1:
			break
	check(main.local_recorder.ticks > 100, "fixed-step simulation advanced while recording")
	main.local_model.winner = 1
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	check(main.last_replay_path != "", "finishing a practice battle saves a replay")
	var replay := BattleReplay.load_file(main.last_replay_path)
	check(not replay.is_empty() and replay.meta.mode == "practice" and bool(BattleReplay.verify(replay).ok), "the practice replay verifies")
	check(load("res://scripts/screens/ReplayScreens.gd").describe(replay).title.begins_with("연습"), "replay list labels it as practice")
	# With practice tools the battle is an experiment and is not recorded.
	main.practice.speed = 2.0
	main._start_local_ai_battle(2)
	check(main.local_recorder == null and main.practice_used_tools, "sped-up practice is not recorded")
	main.practice.speed = 1.0
	main._start_local_ai_battle(2)
	check(main.local_recorder != null, "back to normal speed records again")
	main.practice.cycle_speed()
	main.practice_used_tools = true
	main.local_recorder = null
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://practice_replay_test")
	print("practice_replay_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
