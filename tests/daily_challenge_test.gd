extends SceneTree
## Daily challenge: same day = same challenge for everyone, scoring, history, streaks and the full UI flow.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	check(DailyChallenge.date_key(0) == "19700101" and DailyChallenge.date_key(86400 * 365) == "19710101", "date keys are UTC calendar days")
	var a := DailyChallenge.for_date("20261008")
	var b := DailyChallenge.for_date("20261008")
	check(JSON.stringify(a) == JSON.stringify(b), "the same day always gives the same challenge")
	var distinct := {}
	var modifiers := {}
	var valid := true
	for day in range(1, 61):
		var key := "202611%02d" % day if day <= 30 else "202612%02d" % (day - 30)
		var challenge := DailyChallenge.for_date(key)
		distinct[",".join(PackedStringArray(challenge.units))] = true
		modifiers[challenge.modifier] = true
		valid = valid and BattleModel._valid_deck(challenge.units, BattleModel.UNIT_STATS) and BattleModel._valid_deck(challenge.structures, BattleModel.STRUCTURE_STATS)
		valid = valid and int(challenge.stage) >= DailyChallenge.MIN_STAGE and int(challenge.stage) <= DailyChallenge.MAX_BASE_STAGE and not DailyChallenge.modifier_info(String(challenge.modifier)).is_empty()
	check(valid, "every day produces legal decks, a sane stage and a known twist")
	check(distinct.size() >= 20 and modifiers.size() == DailyChallenge.MODIFIERS.size(), "days vary: %d decks, %d twists" % [distinct.size(), modifiers.size()])

	# Twists change the setup as described.
	var base := {"key": "20261008", "stage": 4, "units": ["shield", "swordsman", "archer"], "structures": ["wall", "swamp", "turret"], "modifier": ""}
	var plain := DailyChallenge.build(base)
	check(plain.stage == 4 and plain.model.base_hp[1] == 380.0 and plain.model.resources[0] > 20.0, "baseline: stage 4 enemy base 380")
	var tweaked := base.duplicate()
	tweaked.modifier = "empty_hands"
	check(DailyChallenge.build(tweaked).model.resources[0] == 20.0, "empty hands: 20 starting resources")
	tweaked.modifier = "iron_fortress"
	check(DailyChallenge.build(tweaked).model.base_hp[1] == BattleModel.BASE_MAX_HP, "iron fortress: enemy base at the cap")
	tweaked.modifier = "rich_enemy"
	check(DailyChallenge.build(tweaked).model.resources[1] == BattleModel.MAX_RESOURCE, "rich enemy: full resources")
	tweaked.modifier = "fragile_base"
	check(DailyChallenge.build(tweaked).model.base_hp[0] == 300.0, "fragile base: 300 health")
	tweaked.modifier = "elite_foe"
	check(DailyChallenge.build(tweaked).stage == 6 and DailyChallenge.effective_stage({"stage": 7, "modifier": "elite_foe"}) == ServerAI.MAX_STAGE, "elite foe: +2 stages, capped at the last stage")

	# Scoring and history.
	check(DailyChallenge.score(false, 500.0, 10.0) == 0, "no points for a loss")
	check(DailyChallenge.score(true, 500.0, 60.0) > DailyChallenge.score(true, 100.0, 60.0), "more base health scores higher")
	check(DailyChallenge.score(true, 300.0, 40.0) > DailyChallenge.score(true, 300.0, 200.0), "faster scores higher")
	check(DailyChallenge.score(true, 0.0, 9999.0) == 100 and DailyChallenge.score(true, 500.0, 0.0) == 2000, "scores stay within 100..3000")
	var save := SaveData.default_data()
	var first := DailyChallenge.record(save, base, true, 400.0, 100.0)
	check(first.new_best and save.stats.daily_completed == 1 and save.daily["20261008"].won, "first win is recorded")
	var worse := DailyChallenge.record(save, base, true, 100.0, 250.0)
	check(not worse.new_best and worse.best == first.score and save.stats.daily_completed == 1, "a worse retry keeps the best score and does not count twice")
	var better := DailyChallenge.record(save, base, true, 500.0, 50.0)
	check(better.new_best and save.daily["20261008"].score == better.score, "a better retry replaces the score")
	var loss_save := SaveData.default_data()
	DailyChallenge.record(loss_save, base, false, 0.0, 30.0)
	check(not loss_save.daily["20261008"].won and loss_save.stats.daily_completed == 0, "a failed attempt is remembered but is not a clear")
	var streak_save := SaveData.default_data()
	for key in ["20261005", "20261006", "20261007"]:
		streak_save.daily[key] = {"won": true, "score": 1000, "seconds": 60.0}
	check(DailyChallenge.streak(streak_save, "20261008") == 3, "a streak that ended yesterday still counts today")
	check(DailyChallenge.streak(streak_save, "20261010") == 0, "a missed day breaks it")
	streak_save.daily["20261008"] = {"won": true, "score": 900, "seconds": 70.0}
	check(DailyChallenge.streak(streak_save, "20261008") == 4, "today extends it")
	check(SaveData.sanitize(JSON.parse_string(JSON.stringify(streak_save))).daily.size() == 4, "history round-trips through the save file")

	# Full UI flow.
	BattleReplay.save_dir = "user://daily_challenge_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	check(main.find_child("DailyButton", true, false) != null, "main menu offers the daily challenge")
	main._show_daily_brief()
	await process_frame
	check(main.find_child("DailyModifier", true, false) != null and main.find_child("DailyDeck", true, false).get_child_count() == 3 and main.find_child("DailyBest", true, false) != null, "the brief shows today's twist, deck and best score")
	main.find_child("StartDailyChallenge", true, false).pressed.emit()
	await process_frame
	var today := DailyChallenge.date_key()
	check(main.daily_challenge.key == today and main.local_recorder != null and main.local_model.unit_decks[0] == main.daily_challenge.units, "starting begins a recorded battle with the fixed deck")
	main.set_process(false)
	# No outside tampering with the model: a recorded battle must stay reproducible from commands alone.
	for i in 90:
		main._process(0.1)
	for kind in main.battle_preset.units:
		main._purchase_unit(kind)
	for i in 30:
		main._process(0.1)
	main.local_model.winner = 0
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	await process_frame
	check(main.save_data.daily.has(today) and main.save_data.daily[today].won and main.save_data.achievements.has("daily_clear"), "winning stores the score and unlocks the daily badge")
	check(main.save_data.stats.ai_matches == 0, "daily battles are not counted as ordinary AI matches")
	var notes: Array = main.result_overlay.find_children("*", "Label", true, false).map(func(label): return label.text)
	check(notes.any(func(text): return text.contains("일일 도전 성공")), "the result screen reports the score")
	check(main.last_replay_path != "", "the battle was saved as a replay")
	var replay := BattleReplay.load_file(main.last_replay_path)
	check(not replay.is_empty() and replay.meta.mode == "daily" and replay.meta.date == today and bool(BattleReplay.verify(replay).ok), "the daily replay verifies and carries its date")
	check(load("res://scripts/screens/ReplayScreens.gd").describe(replay).title.begins_with("일일 도전"), "the list names it as a daily challenge")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://daily_challenge_test")
	print("daily_challenge_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
