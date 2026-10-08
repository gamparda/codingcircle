extends SceneTree
## Starter goals: derived and flag-based progress, persistence, the menu chip, the list and the result-screen hints.

const Goals = preload("res://scripts/Goals.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var save := SaveData.default_data()
	check(Goals.done_count(save) == 0 and Goals.next_goal(save).id == "first_win" and not Goals.all_done(save), "a fresh save has nothing done and starts with the first win")
	save.stats.highest_campaign = 1
	check(Goals.is_done(save, "first_win") and Goals.next_goal(save).id == "edit_deck", "a campaign clear completes the first goal")
	save.stats.daily_completed = 1
	save.stats.online_completed = 2
	check(Goals.is_done(save, "daily") and Goals.is_done(save, "online"), "daily and online goals come from the statistics")
	Goals.mark(save, "draft")
	Goals.mark(save, "not_a_goal")
	check(Goals.is_done(save, "draft") and not save.goals.has("not_a_goal"), "flag goals are marked, unknown ids ignored")
	var before := Goals.done_ids(save)
	Goals.mark(save, "edit_deck")
	check(Goals.gained(save, before).map(func(entry): return entry.id) == ["edit_deck"], "gained lists only what was completed since")
	Goals.mark(save, "watch_replay")
	check(Goals.all_done(save) and Goals.next_goal(save).is_empty(), "everything done leaves no next goal")
	var stored := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(stored.goals.has("draft") and stored.goals.has("edit_deck") and Goals.all_done(stored), "goals survive saving")
	var junk := SaveData.sanitize({"goals": {"draft": "yes", "edit_deck": true, "bogus": true}})
	check(junk.goals == {"edit_deck": true}, "junk flags are dropped")
	var lines := Goals.result_lines(SaveData.default_data(), [])
	check(lines.size() == 1 and lines[0].tone == "muted" and lines[0].text.begins_with("다음 추천"), "with nothing new the result screen only suggests the next goal")

	BattleReplay.save_dir = "user://goals_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	main._build_connect_screen()
	await process_frame
	check(main.find_child("GoalsChip", true, false) != null and main.find_child("GoalsChip", true, false).text.contains("0 / %d" % Goals.DEFS.size()), "the menu shows the progress chip")
	main.find_child("GoalsChip", true, false).pressed.emit()
	await process_frame
	check(main.find_child("GoalList", true, false).get_child_count() == Goals.DEFS.size() and main.find_child("GoalGo_first_win", true, false) != null, "the list has a row and a shortcut per open goal")
	main.find_child("GoalGo_draft", true, false).pressed.emit()
	await process_frame
	check(main.find_child("DraftPool", true, false) != null, "a shortcut opens the matching screen")
	# Saving a deck, watching a replay and drafting mark their goals.
	main._build_deck_screen()
	await process_frame
	main.find_child("DeckSaveButton", true, false).pressed.emit()
	await process_frame
	check(Goals.is_done(main.save_data, "edit_deck"), "saving a deck completes its goal")
	var model := BattleModel.new()
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {}, {"mode": "quick"})
	for tick in 30:
		model.tick(1.0 / 30.0)
		recorder.on_tick()
	model.winner = 0
	var path := BattleReplay.save(recorder.finish(model), "goals")
	main._play_replay(path)
	await process_frame
	check(Goals.is_done(main.save_data, "watch_replay"), "opening a replay completes its goal")
	main._start_draft_battle(["shield", "archer", "healer"], ["berserker", "warlock", "necromancer"], 2)
	check(Goals.is_done(main.save_data, "draft"), "starting a draft battle completes its goal")
	# A first campaign win shows the achievement and the next suggestion on the result screen.
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	main.campaign_mode = true
	main._start_local_ai_battle(1)
	main.set_process(false)
	main.local_model.winner = 0
	main.local_model.elapsed = 50.0
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	await process_frame
	var hints: Array = main.find_child("GoalHints", true, false).get_children().map(func(label): return label.text)
	check(hints.size() == 2 and hints[0].begins_with("목표 달성 ▸ 첫 승리") and hints[1].begins_with("다음 추천 ▸ 내 덱 만들기"), "the result screen reports the goal and the next one: %s" % [hints])
	for file in BattleReplay.list_saved():
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute("user://goals_test")
	print("goals_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
