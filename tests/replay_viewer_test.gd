extends SceneTree
## Replay list and viewer: list a saved replay, play it to the end, scrub, restart and leave.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

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

	var replay := _make_replay()
	var saved := BattleReplay.save(replay, "viewer-test")
	check(saved != "", "test replay saved")
	main._build_replay_list()
	await process_frame
	var cards = main.find_children("ReplayCard", "PanelContainer", true, false)
	check(cards.size() == 1, "saved replay is listed once")
	check(main.find_child("PlayReplayButton", true, false) != null and main.find_child("DeleteReplayButton", true, false) != null, "card offers play and delete")

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
	main.find_child("DeleteReplayButton", true, false).pressed.emit()
	await process_frame
	check(not FileAccess.file_exists(saved), "delete removes the file")
	DirAccess.remove_absolute("user://replay_viewer_test")
	print("replay_viewer_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
