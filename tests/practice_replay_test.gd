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
	# A failed replay write must survive leaving the result and starting another match.
	var saved_dir := BattleReplay.save_dir
	BattleReplay.save_dir = "user://practice_replay_blocked"
	var blocker := FileAccess.open(BattleReplay.save_dir, FileAccess.WRITE)
	blocker.store_string("block replay directory")
	blocker.close()
	var matches_before: int = main.save_data.stats.ai_matches
	for stage in [1, 2]:
		main._start_local_ai_battle(stage)
		main._process(0.1)
		main.local_model.winner = 1
		main._on_snapshot(main.local_model.snapshot())
		await process_frame
		check(main.last_replay_path.is_empty() and main.local_recorder == null, "failed save preserves the finished data rather than the live recorder")
		check(main.find_child("RetryBattleReplaySave", true, false) != null and not main.updater.safe_to_update, "replay failure offers retry and defers updates")
		main._show_result(1)
		check(main.pending_battle_replays.size() == stage, "showing a result twice does not queue a duplicate")
		main._build_connect_screen()
		await process_frame
		check(main.find_child("ReplaySaveWarning", true, false) != null, "replay warning survives returning to the menu")
	check(main.save_data.stats.ai_matches == matches_before + 2, "failed replay storage does not prevent result accounting")
	check(main._save_profile() and not main.updater.safe_to_update, "saving the profile cannot resume updates while a replay is unsaved")
	DirAccess.make_dir_absolute(SaveData.SAVE_PATH + ".tmp")
	check(not main._save_profile(), "profile and replay failures can be pending together")
	await process_frame
	var profile_warning := main.find_child("ProfileSaveWarning", true, false) as Control
	var replay_warning := main.find_child("ReplaySaveWarning", true, false) as Control
	check(not profile_warning.get_global_rect().intersects(replay_warning.get_global_rect()), "both save failures and retry buttons remain separately visible")
	DirAccess.remove_absolute(SaveData.SAVE_PATH + ".tmp")
	main.find_child("RetryProfileSave", true, false).pressed.emit()
	check(not main.profile_save_pending and not main.updater.safe_to_update, "profile retry still waits for pending replays before updating")
	main._retry_battle_replays()
	check(main.pending_battle_replays.size() == 2, "retry while storage is blocked keeps both finished battles")
	DirAccess.remove_absolute(BattleReplay.save_dir)
	main.find_child("RetryBattleReplaySave", true, false).pressed.emit()
	await process_frame
	check(main.pending_battle_replays.is_empty() and main.find_child("ReplaySaveWarning", true, false) == null, "successful retry clears the pending replays and warning")
	check(main.updater.safe_to_update and main.save_data.stats.ai_matches == matches_before + 2, "retry resumes updates without counting the matches again")
	var recovered := BattleReplay.list_saved()
	check(recovered.size() == 2, "each failed battle is recovered exactly once")
	for path in recovered:
		check(bool(BattleReplay.verify(BattleReplay.load_file(path)).ok), "recovered replay reproduces its own finished battle")
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(BattleReplay.save_dir)
	BattleReplay.save_dir = saved_dir
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
	# A recording-limit failure has no recoverable data, so it must not offer endless retries.
	main.practice.speed = 1.0
	main._start_local_ai_battle(2)
	main.local_recorder.ticks = BattleReplay.MAX_TICKS
	main.local_recorder.on_tick()
	main.local_model.winner = 1
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	check(main.pending_battle_replays.is_empty() and main.find_child("RetryBattleReplaySave", true, false) == null, "over-limit recording never enters the storage retry queue")
	check(main.find_child("ReplaySaveWarning", true, false) != null and main.replay_recording_error.contains("기록 한도"), "the result explains why the over-limit replay cannot be saved")
	main._start_local_ai_battle(2)
	check(main.replay_recording_error.is_empty(), "a new battle clears the previous recording-limit notice")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://practice_replay_test")
	print("practice_replay_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
