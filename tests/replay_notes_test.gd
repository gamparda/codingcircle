extends SceneTree
## Replay notes: validation, helpers, share text, verification and the viewer controls.

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
	var noted := BattleReplay.with_note(replay, 100, "첫 교전")
	check(BattleReplay.notes_of(replay).is_empty() and BattleReplay.notes_of(noted).size() == 1, "adding a note returns a copy")
	check(BattleReplay.valid(noted) and bool(BattleReplay.verify(noted).ok), "notes do not affect verification")
	var again := BattleReplay.with_note(noted, 100, "고쳐 씀")
	check(BattleReplay.notes_of(again).size() == 1 and BattleReplay.notes_of(again)[0].text == "고쳐 씀", "a note on the same tick is replaced")
	var two := BattleReplay.with_note(again, 50, "먼저")
	check(BattleReplay.notes_of(two)[0].t == 50, "notes stay sorted by tick")
	check(BattleReplay.with_note(replay, 10, "   ") == replay and BattleReplay.with_note(replay, total + 5, "끝 너머") == replay, "empty text and ticks past the end are refused")
	check(BattleReplay.notes_of(BattleReplay.with_note(replay, 3, "가".repeat(100)))[0].text.length() == BattleReplay.MAX_NOTE_LENGTH, "long text is cut to the limit")
	var full := replay
	for i in BattleReplay.MAX_NOTES:
		full = BattleReplay.with_note(full, i * 10, "메모 %d" % i)
	check(BattleReplay.notes_of(full).size() == BattleReplay.MAX_NOTES and BattleReplay.with_note(full, 9999, "넘침") == full, "the list is bounded")
	check(BattleReplay.notes_of(BattleReplay.without_note(two, 50)).size() == 1 and not BattleReplay.without_note(BattleReplay.without_note(two, 50), 100).has("notes"), "notes can be removed")
	check(BattleReplay.nearest_note(two, 70)["t"] == 50 and BattleReplay.nearest_note(two, 5000).is_empty(), "nearest note respects the tolerance")
	var restored := BattleReplay.from_share_text(BattleReplay.to_share_text(two))
	check(not restored.is_empty() and BattleReplay.notes_of(restored).size() == 2, "notes survive share text")
	for bad in [[{"t": -1, "text": "x"}], [{"t": 5, "text": ""}], [{"t": 5, "text": "x"}, {"t": 5, "text": "y"}], [{"t": 5}], "nope", [{"t": total + 100, "text": "x"}], [{"t": 5, "text": "a" + char(10) + "b"}]]:
		var broken: Dictionary = JSON.parse_string(JSON.stringify(replay))
		broken["notes"] = bad
		check(not BattleReplay.valid(broken), "rejects bad notes %s" % [bad])

	BattleReplay.save_dir = "user://replay_notes_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	var path := BattleReplay.save(replay, "notes-test")
	main._play_replay(path)
	await process_frame
	var viewer = main.replay_viewer
	var changes := []
	viewer.notes_changed.connect(func(updated): changes.append(updated))
	viewer.seek(200)
	check(not viewer.add_note(), "an empty input adds nothing")
	viewer.note_input.text = "여기서 밀렸다"
	check(viewer.add_note() and viewer.note_input.text == "" and changes.size() == 1, "the button pins a note and reports it")
	check(BattleReplay.notes_of(BattleReplay.load_file(path)).size() == 1 and BattleReplay.notes_of(BattleReplay.load_file(path))[0].t == viewer.player.ticks, "the note is written back to the replay file")
	check(viewer.graph.notes.size() == 1, "the timeline shows a marker")
	viewer.seek(150)
	viewer._announce_between(150, 250)
	check(viewer.moment_toast.text.begins_with("메모 ▸"), "playing past a note announces it")
	viewer.seek(400)
	check(not viewer.delete_note(), "nothing is deleted when no note is near")
	viewer.seek(210)
	check(viewer.delete_note() and BattleReplay.notes_of(BattleReplay.load_file(path)).is_empty(), "the nearest note can be deleted")
	main._build_replay_list()
	await process_frame
	var kept := BattleReplay.with_note(replay, 100, "목록 표시")
	BattleReplay.write_file(path, kept)
	main._build_replay_list()
	await process_frame
	check(main.find_children("*", "Label", true, false).any(func(label): return label.text.contains("메모 1개")), "the list shows how many notes a replay has")
	for file in BattleReplay.list_saved():
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute("user://replay_notes_test")
	print("replay_notes_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
