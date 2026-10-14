extends SceneTree
## Replay list and viewer: list a saved replay, play it to the end, scrub, restart and leave.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func _confirm(main, button_name: String) -> void:
	# Destructive replay actions now ask for confirmation in a dialog first.
	await process_frame
	var button := main.find_child(button_name, true, false) as Button
	if button != null:
		button.pressed.emit()
	await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _make_replay() -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	model.configure_deck(1, ["berserker", "warlock", "necromancer"], ["wall", "turret", "generator"])
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {}, {"mode": "quick"})
	var tick := 0
	while model.winner == -1 and tick < 30 * 400:
		if tick % 40 == 0 and model.spawn_unit(0, "swordsman"):
			recorder.on_spawn(0, "swordsman")
		if tick % 55 == 0 and model.spawn_unit(1, "berserker"):
			recorder.on_spawn(1, "berserker")
		model.tick(1.0 / 30.0)
		recorder.on_tick()
		tick += 1
	return recorder.finish(model)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	BattleReplay.save_dir = "user://replay_viewer_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	check(main.find_child("ReplaysButton", true, false) != null, "main menu offers the replay list")

	# Empty state when nothing is saved (use a clean directory listing).
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	main._build_replay_list()
	await process_frame
	check(main.find_child("NoReplays", true, false) != null, "empty replay list explains how replays appear")
	var unreadable := BattleReplay.save_dir.path_join("damaged.json")
	DirAccess.make_dir_recursive_absolute(BattleReplay.save_dir)
	var invalid := FileAccess.open(unreadable, FileAccess.WRITE)
	invalid.store_string("[]")
	invalid.close()
	main._build_replay_list()
	await process_frame
	check(main.find_child("UnreadableReplayCard", true, false) != null and main.find_child("NoReplays", true, false) == null, "unreadable saved files are visible rather than reported as an empty library")
	check(main.find_child("PlayReplayButton", true, false) == null and main.find_child("ReplayStatus", true, false).text.contains("1개"), "unreadable replay cannot be played and the list explains the problem")
	main.find_child("DeleteReplayButton", true, false).pressed.emit()
	await _confirm(main, "ConfirmReplayDelete")
	check(not FileAccess.file_exists(unreadable) and main.find_child("NoReplays", true, false) != null, "an unreadable replay can be deleted from the list")

	var replay := _make_replay()
	var saved := BattleReplay.save(replay, "viewer-test")
	check(saved != "", "test replay saved")
	main._build_replay_list()
	await process_frame
	var cards = main.find_children("ReplayCard", "PanelContainer", true, false)
	check(cards.size() == 1, "saved replay is listed once")
	check(main.find_child("PlayReplayButton", true, false) != null and main.find_child("DeleteReplayButton", true, false) != null, "card offers play and delete")

	# Import from share text adds a second card; garbage is refused with a message.
	var ReplayScreens = load("res://scripts/screens/ReplayScreens.gd")
	check(ReplayScreens.import_text(main, "not a replay").contains("가져올 수 없습니다"), "garbage import is refused")
	var message: String = ReplayScreens.import_text(main, BattleReplay.to_share_text(replay))
	await process_frame
	check(message.contains("가져왔"), "valid share text is imported: %s" % message)
	# Sibling nodes with one name get auto-renamed, so count the row container's children instead.
	check(main.find_child("ReplayRows", true, false).get_child_count() == 2, "imported replay appears in the list")
	check(main.find_child("ShareReplayButton", true, false) != null and main.find_child("ImportReplayButton", true, false) != null, "list offers copy and import")
	main._play_replay(saved)
	var viewer = main.replay_viewer
	# Checked before any frame runs: how far a frame advances depends on the machine's frame time.
	check(viewer != null and viewer.player != null and viewer.player.ticks == 0, "viewer starts at the beginning")
	await process_frame
	for i in 5:
		viewer._process(0.1) # fixed deltas keep this independent of the machine's frame rate
	check(viewer.player.ticks >= 10, "playback advances with elapsed time")
	viewer.seek(int(replay.result.ticks) / 2)
	check(viewer.player.ticks >= int(replay.result.ticks) / 2 - 1 and not viewer.player.is_finished(), "seek jumps to the middle of the battle")
	viewer.cycle_speed()
	check(viewer.speed_button.text == "2배속", "speed button cycles")
	viewer.toggle_pause()
	var frozen: int = viewer.player.ticks
	for i in 5:
		await process_frame
	check(viewer.player.ticks == frozen, "pause stops playback")
	viewer.toggle_pause()
	viewer.seek(int(replay.result.ticks))
	for i in 3:
		await process_frame
	check(viewer.player.is_finished() and viewer.player.model.state_hash() == String(replay.result.state_hash), "playing to the end reproduces the recorded result")
	viewer._process(0.1)
	check(viewer.find_child("ReplayEndBanner", true, false) != null, "end banner announces the winner")
	viewer._restart()
	check(viewer.player.ticks == 0 and not viewer.finished_shown, "restart rewinds to the beginning")
	await process_frame
	viewer.find_child("ReplayClose", true, false).pressed.emit()
	await process_frame
	await process_frame
	check(main.find_child("ReplayRows", true, false) != null and main.find_child("ReplayViewer", true, false) == null, "leaving returns to the list")
	var deleted: String = BattleReplay.list_saved()[0] # the list shows the newest (imported) replay first
	var delete_button: Button = main.find_child("DeleteReplayButton", true, false)
	DirAccess.rename_absolute(deleted, deleted + ".hold")
	DirAccess.make_dir_absolute(deleted)
	var blocked := FileAccess.open(deleted.path_join("keep.txt"), FileAccess.WRITE)
	blocked.store_string("keep")
	blocked.close()
	delete_button.pressed.emit()
	await process_frame
	check(main.find_child("DeleteReplayButton", true, false) == delete_button and main.find_child("ReplayRows", true, false).get_child_count() == 2, "failed deletion keeps the displayed replay and its retry action")
	var blocked_confirm := main.find_child("ConfirmReplayDelete", true, false) as Button
	check(main.find_child("ReplayDeleteStatus", true, false).text.contains("접근할 수 없") and blocked_confirm != null and blocked_confirm.disabled, "a path that is no longer a file cannot be confirmed for deletion and the dialog explains why")
	check(FileAccess.file_exists(deleted.path_join("keep.txt")), "a directory at a replay path is never recursively deleted")
	main.find_child("CancelReplayDelete", true, false).pressed.emit()
	await process_frame
	DirAccess.remove_absolute(deleted.path_join("keep.txt"))
	DirAccess.remove_absolute(deleted)
	DirAccess.rename_absolute(deleted + ".hold", deleted)
	main.find_child("DeleteReplayButton", true, false).pressed.emit()
	await _confirm(main, "ConfirmReplayDelete")
	check(not FileAccess.file_exists(deleted), "delete removes the file shown by that card")
	# A library above the retention bound explains cleanup failure and offers a retry.
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	var small_model := BattleModel.new()
	small_model.winner = 0
	var small_replay := BattleReplay.Recorder.new(small_model).finish(small_model)
	for index in BattleReplay.MAX_SAVED + 1:
		BattleReplay.write_file(BattleReplay.save_dir.path_join("20261011_%02d.json" % index), small_replay)
	main._build_replay_list()
	# The shelf now reads files in short batches; wait for the scan to finish.
	for _i in 600:
		await process_frame
		if main.find_child("RetryReplayCleanup", true, false) != null: break
	check(main.find_child("ReplayStatus", true, false).text.contains("51개") and main.find_child("RetryReplayCleanup", true, false) != null, "over-limit library shows actual count and cleanup retry")
	main.find_child("RetryReplayCleanup", true, false).pressed.emit()
	await _confirm(main, "ConfirmReplayCleanup")
	check(BattleReplay.list_saved().size() == BattleReplay.MAX_SAVED and main.find_child("RetryReplayCleanup", true, false) == null, "cleanup retry trims oldest files and clears the warning")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://replay_viewer_test")
	print("replay_viewer_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
