extends SceneTree
## Momentum curve, highlights and the viewer's "jump to next moment" controls.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ReplayAnalysis = preload("res://scripts/ReplayAnalysis.gd")
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
	var replay := _make_replay()
	var analysis := ReplayAnalysis.analyze(replay)
	check(int(analysis.ticks) == int(replay.result.ticks), "analysis covers the whole battle")
	check(analysis.samples.size() >= int(analysis.ticks) / ReplayAnalysis.SAMPLE_TICKS - 1, "one sample per half second")
	check(analysis.samples.all(func(sample): return float(sample.momentum) >= -1.0 and float(sample.momentum) <= 1.0), "momentum stays within -1..1")
	var highlights: Array = analysis.highlights
	check(highlights.size() >= 2 and highlights.size() <= ReplayAnalysis.MAX_HIGHLIGHTS, "a handful of highlights: %d" % highlights.size())
	check(highlights.back().kind == "finish" and int(highlights.back().tick) == int(analysis.ticks), "the last highlight is the finishing blow")
	var sorted := true
	for i in range(1, highlights.size()):
		sorted = sorted and int(highlights[i].tick) >= int(highlights[i - 1].tick)
	check(sorted, "highlights are in time order")
	check(ReplayAnalysis.analyze(replay).highlights == highlights, "analysis is deterministic")
	check(ReplayAnalysis.analyze({}).samples.is_empty(), "invalid replays produce an empty analysis")
	check(ReplayAnalysis.next_after(highlights, int(analysis.ticks)).is_empty(), "nothing comes after the end")
	check(ReplayAnalysis.next_after(highlights, -10).tick == highlights[0].tick, "next_after finds the first highlight")

	BattleReplay.save_dir = "user://replay_analysis_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	var saved := BattleReplay.save(replay, "analysis-test")
	main._play_replay(saved)
	await process_frame
	var viewer = main.replay_viewer
	check(viewer.graph != null and viewer.graph.highlights.size() == highlights.size(), "viewer draws the momentum graph with its highlights")
	viewer.toggle_pause()
	viewer.jump_next_moment()
	var first_target: int = int(highlights[0].tick) - viewer.JUMP_LEAD_TICKS
	check(viewer.player.ticks == maxi(0, first_target), "next moment lands a second before the first highlight")
	var landed: int = viewer.player.ticks
	viewer.jump_next_moment()
	check(viewer.player.ticks > landed or highlights.size() < 2, "pressing again moves on to the following moment")
	viewer.jump_previous_moment()
	check(viewer.player.ticks <= landed + 1, "previous moment goes back")
	viewer.graph.seek_requested.emit(int(replay.result.ticks) / 2)
	check(absi(viewer.player.ticks - int(replay.result.ticks) / 2) <= 1, "clicking the graph seeks")
	var mid_marker: Dictionary = viewer.graph.nearest_highlight(viewer.graph._x_for(int(highlights[0].tick)))
	check(not mid_marker.is_empty() and mid_marker.tick == highlights[0].tick, "markers can be hit by position")
	viewer.seek(maxi(0, int(highlights[0].tick) - 2))
	viewer.toggle_pause()
	viewer._process(0.2)
	check(viewer.moment_toast.text != "" or int(highlights[0].tick) <= 2, "playing past a highlight announces it")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://replay_analysis_test")
	print("replay_analysis_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
