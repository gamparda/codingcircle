extends SceneTree
## Replay list: open by code, recent online battles and per-replay code sharing, including the offline messages.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	BattleReplay.save_dir = "user://replay_code_ui_test"
	var model := BattleModel.new()
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {}, {"mode": "quick"})
	for tick in 60:
		model.tick(1.0 / 30.0)
		recorder.on_tick()
	model.winner = 0
	BattleReplay.save(recorder.finish(model), "code-ui")
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main._build_replay_list()
	await process_frame
	check(main.find_child("OpenByCodeButton", true, false) != null and main.find_child("RecentBattlesButton", true, false) != null, "the footer offers both entry points")
	var share: Button = main.find_child("ShareCodeButton", true, false)
	check(share != null, "each replay card can be shared by code")
	share.pressed.emit()
	check(share.text.contains("접속"), "sharing offline says a connection is needed")
	main.find_child("OpenByCodeButton", true, false).pressed.emit()
	await process_frame
	var input: LineEdit = main.find_child("ReplayCodeInput", true, false)
	check(input != null and input.max_length == 6, "the code dialog has a six-character input")
	input.text = "abc234"
	input.text_changed.emit("abc234")
	check(input.text == "ABC234", "the code is upper-cased as typed")
	main.find_child("OpenReplayCode", true, false).pressed.emit()
	check(main.find_child("ReplayCodeStatus", true, false).text.contains("접속"), "opening offline explains why it cannot")
	main.find_child("CloseReplayCode", true, false).pressed.emit()
	await process_frame
	main.find_child("RecentBattlesButton", true, false).pressed.emit()
	await process_frame
	check(main.find_child("RecentBattlesStatus", true, false).text.contains("접속"), "the recent list offline explains why it is empty")
	# A list that arrives from a server gets one row per battle and can be watched.
	main._dismiss_action_overlay()
	await process_frame
	var replay_row = load("res://scripts/screens/ReplayScreens.gd")._recent_row(main, {"code": "ABC234", "winner": 1, "ticks": 900, "units": [["shield", "archer", "healer"], ["berserker", "warlock", "necromancer"]]})
	main.add_child(replay_row)
	check(replay_row.find_child("WatchRecentBattle", true, false) != null, "recent rows have a watch button")
	for file in BattleReplay.list_saved():
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute("user://replay_code_ui_test")
	print("replay_code_ui_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
