extends SceneTree
## Highlight clips: a replay plus a window, shareable as text, honoured by the viewer.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _replay() -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	model.configure_deck(1, ServerAI.stage_unit_deck(3), ServerAI.stage_structure_deck(3))
	var ai := ServerAI.new(1, 3)
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": 3}, {"mode": "campaign", "stage": 3})
	var tick := 0
	while model.winner == -1 and tick < 30 * 200:
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
	var replay := _replay()
	var total := int(replay.result.ticks)
	var clip := BattleReplay.make_clip(replay, total / 2, "한가운데")
	check(BattleReplay.valid(clip) and bool(BattleReplay.verify(clip).ok), "a clip is a valid, verifying replay")
	check(int(clip.clip.start) == total / 2 - 300 and int(clip.clip.end) == total / 2 + 300, "the window is ten seconds either side")
	check(not replay.has("clip") and BattleReplay.clip_of(replay).is_empty(), "making a clip does not modify the original")
	var early := BattleReplay.make_clip(replay, 5, "시작")
	check(int(early.clip.start) == 0 and int(early.clip.end) == 305, "the window is clamped at the start")
	var late := BattleReplay.make_clip(replay, total + 5000, "끝")
	check(int(late.clip.end) <= total and int(late.clip.start) < int(late.clip.end), "the window is clamped at the end")
	var restored := BattleReplay.from_share_text(BattleReplay.to_share_text(clip))
	check(not restored.is_empty() and restored.clip.title == "한가운데" and int(restored.clip.start) == int(clip.clip.start), "clips survive share text")
	for bad in [{"start": 10, "end": 10}, {"start": -5, "end": 20}, {"start": 0, "end": 99999999}, {"start": "a", "end": 5}, "nope", {"start": 1, "end": 9, "title": "x".repeat(200)}]:
		var broken: Dictionary = JSON.parse_string(JSON.stringify(replay))
		broken["clip"] = bad
		check(not BattleReplay.valid(broken), "rejects bad clip window %s" % [bad])

	BattleReplay.save_dir = "user://replay_clip_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	var saved := BattleReplay.save(clip, "clip-test")
	main._build_replay_list()
	await process_frame
	check(main.find_children("*", "Label", true, false).any(func(label): return label.text.begins_with("클립 ▸")), "the list marks clips")
	main._play_replay(saved)
	await process_frame
	var viewer = main.replay_viewer
	check(absi(viewer.player.ticks - int(clip.clip.start)) <= 6, "the viewer opens at the clip start (%d vs %d)" % [viewer.player.ticks, int(clip.clip.start)])
	check(viewer.moment_toast.text.begins_with("클립 ▸"), "and says what the clip is")
	var guard := 0
	while not viewer.clip_finished and guard < 400:
		viewer._process(0.25)
		guard += 1
	check(viewer.clip_finished and viewer.paused and absi(viewer.player.ticks - int(clip.clip.end)) <= 10, "playback pauses at the clip end (%d vs %d)" % [viewer.player.ticks, int(clip.clip.end)])
	check(viewer.moment_toast.text.begins_with("클립 끝"), "and tells the player")
	viewer.toggle_pause()
	viewer._process(0.25)
	check(viewer.player.ticks > int(clip.clip.end) - 10, "resuming plays on past the end")
	viewer._restart()
	check(absi(viewer.player.ticks - int(clip.clip.start)) <= 6 and not viewer.clip_finished, "restart returns to the clip start")

	# Copying a clip from a full replay centres it on the nearest highlight.
	main._play_replay(BattleReplay.save(replay, "full"))
	await process_frame
	var full_viewer = main.replay_viewer
	var target: Dictionary = full_viewer.analysis.highlights[0]
	full_viewer.seek(int(target.tick) + 40)
	var text: String = full_viewer.copy_clip()
	var copied := BattleReplay.from_share_text(text)
	check(not copied.is_empty() and copied.clip.title == target.text, "the clip is titled after the nearest highlight: %s" % [copied.get("clip", {})])
	check(absi((int(copied.clip.start) + int(copied.clip.end)) / 2 - int(target.tick)) <= 2 or int(copied.clip.start) == 0, "and centred on it")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://replay_clip_test")
	print("replay_clip_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
