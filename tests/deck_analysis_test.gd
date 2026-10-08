extends SceneTree
## Battle summary line, per-deck aggregation of saved replays and the analysis dialog.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ReplayAnalysis = preload("res://scripts/ReplayAnalysis.gd")
const DeckAnalysis = preload("res://scripts/DeckAnalysis.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _battle(units: Array, stage: int, mode: String, seconds_cap: int, winner_hint: int) -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, units, ["wall", "swamp", "turret"])
	model.configure_deck(1, ServerAI.stage_unit_deck(stage), ServerAI.stage_structure_deck(stage))
	model.configure_base_health(1, 300.0 + float(stage) * 20.0)
	var ai := ServerAI.new(1, stage)
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": stage}, {"mode": mode, "stage": stage})
	var step := 1.0 / float(BattleReplay.DEFAULT_HZ)
	var tick := 0
	while model.winner == -1 and tick < 30 * seconds_cap:
		if tick % 60 == 0 and model.spawn_unit(0, units[(tick / 60) % 3]):
			recorder.on_spawn(0, units[(tick / 60) % 3])
		ai.update(model, step)
		model.tick(step)
		recorder.on_tick()
		tick += 1
	if model.winner == -1:
		model.winner = winner_hint
	return recorder.finish(model)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	# Summary line wording for each story.
	var line := ReplayAnalysis.summary_line
	check(line.call([0.1, 0.2, 0.3, 0.4, 0.5], 0, 0).contains("안정적"), "wire-to-wire win")
	check(line.call([0.1, -0.4, -0.5, -0.4, -0.5, -0.4, -0.5, 0.2, 0.6], 0, 0).contains("역전승"), "comeback win")
	check(not line.call([0.1, -0.4, -0.5, 0.2, 0.6, 0.5], 0, 0).contains("역전승"), "a dip shorter than three seconds is not a comeback")
	check(line.call([0.0, -0.2, 0.1, 0.0, 0.2], 0, 0).contains("접전"), "narrow win")
	check(line.call([0.5, 0.4, 0.5, 0.4, 0.5, 0.4, -0.2, -0.6], 1, 0).contains("전세를 내줬"), "blown lead")
	check(not line.call([0.5, 0.4, -0.2, -0.6], 1, 0).contains("전세를 내줬"), "a brief early lead is not a blown lead")
	check(line.call([-0.1, -0.3, -0.4, -0.5], 1, 0).contains("처음부터 밀렸"), "dominated")
	check(line.call([-0.3, -0.5, -0.4, -0.7], 1, 1).contains("안정적") and line.call([0.2, 0.4, 0.5, 0.6], 0, 1).contains("처음부터"), "perspective flips for the red side")
	check(line.call([0.0, 0.0, 0.0, 0.0], 2, 0).contains("무승부"), "draw")
	check(line.call([0.1], 0, 0) == "" and line.call([0.1, 0.2, 0.3, 0.4], -1, 0) == "", "too little data gives no sentence")
	# Before anyone has fought, deploying first must not look like a lead (or a "reversal" when the other side follows).
	var quiet_model := BattleModel.new()
	quiet_model.resources = [200.0, 200.0]
	quiet_model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	quiet_model.configure_deck(1, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	var quiet := BattleReplay.Recorder.new(quiet_model, BattleReplay.DEFAULT_HZ, {}, {"mode": "quick"})
	for tick in 140:
		if tick == 0 and quiet_model.spawn_unit(1, "swordsman"):
			quiet.on_spawn(1, "swordsman")
		if tick == 60 and quiet_model.spawn_unit(0, "swordsman"):
			quiet.on_spawn(0, "swordsman")
		if tick == 61 and quiet_model.spawn_unit(0, "archer"):
			quiet.on_spawn(0, "archer")
		quiet_model.tick(1.0 / 30.0)
		quiet.on_tick()
	var quiet_analysis := ReplayAnalysis.analyze(quiet.finish(quiet_model))
	check(quiet_analysis.samples.slice(0, 20).all(func(sample): return float(sample.momentum) == 0.0) and not quiet_analysis.highlights.any(func(item): return item.kind == "swing"), "no lead and no reversal before the first fight")
	check(quiet_analysis.samples.any(func(sample): return float(sample.momentum) > 0.3), "the curve moves once the armies meet")
	var snapshot := {"base_hp": [500.0, 100.0], "units": [{"side": 0, "hp": 50.0}, {"side": 1, "hp": 10.0}]}
	check(ReplayAnalysis.momentum_from_snapshot(snapshot) > 0.5, "snapshot momentum favours the stronger side")
	check(ReplayAnalysis.momentum_from_snapshot({"base_hp": [0.0, 0.0], "units": []}) == 0.0, "empty snapshot is neutral")

	BattleReplay.save_dir = "user://deck_analysis_test"
	var tank_deck := ["shield", "swordsman", "archer"]
	var mage_deck := ["healer", "warlock", "necromancer"]
	BattleReplay.save(_battle(tank_deck, 1, "campaign", 200, 0), "a")
	BattleReplay.save(_battle(tank_deck, 2, "practice", 200, 0), "b")
	BattleReplay.save(_battle(mage_deck, 6, "campaign", 60, 1), "c")
	var online := _battle(tank_deck, 1, "campaign", 30, 1)
	online.meta.mode = "quick" # online replays do not say which side is "me", so they are ignored
	BattleReplay.save(online, "d")
	var rows := DeckAnalysis.collect(BattleReplay.list_saved())
	check(rows.size() == 2, "two decks played locally (online replays ignored): %d" % rows.size())
	if rows.size() == 2:
		check(rows[0].games >= rows[1].games, "most played deck first")
		var tank: Dictionary = rows[0] if rows[0].deck[0] == "shield" else rows[1]
		check(tank.games == 2 and tank.wins + tank.losses + tank.draws <= 2 and tank.average_seconds > 0.0, "tank deck aggregates both battles")
		check(not tank.hardest_stage.is_empty() and tank.hardest_stage.stage in [1, 2], "hardest stage is reported")
		var mage: Dictionary = rows[0] if rows[0].deck[0] == "healer" else rows[1]
		check(mage.losses == 1 and mage.win_rate == 0.0 and mage.hardest_stage.stage == 6, "the lost stage-6 battle shows as hardest")
		check(mage.tips.any(func(tip): return tip.contains("앞줄")), "deck without a frontline gets that advice")

	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main._build_replay_list()
	await process_frame
	main.find_child("DeckAnalysisButton", true, false).pressed.emit()
	await process_frame
	check(main.find_child("DeckAnalysisRows", true, false).get_child_count() == 2, "dialog lists both decks")
	check(main.find_child("DeckAnalysisHeadline", true, false).text.contains("판"), "rows describe the record")
	main.find_child("CloseDeckAnalysis", true, false).pressed.emit()
	await process_frame
	check(main.find_child("DeckAnalysisRows", true, false) == null, "dialog closes")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://deck_analysis_test")
	main._build_replay_list()
	await process_frame
	main.find_child("DeckAnalysisButton", true, false).pressed.emit()
	await process_frame
	check(main.find_child("NoDeckAnalysis", true, false) != null, "empty history explains itself")
	print("deck_analysis_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
