extends SceneTree
## Weekly challenge: Monday-keyed, two twists, its own save store, leaderboard keys and the UI flow.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const ServerDailyBoard = preload("res://scripts/ServerDailyBoard.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _unix(year: int, month: int, day: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 12, "minute": 0, "second": 0}))

func _init() -> void:
	call_deferred("run")

func run() -> void:
	check(DailyChallenge.week_key(_unix(2026, 10, 5)) == "20261005" and DailyChallenge.week_key(_unix(2026, 10, 8)) == "20261005" and DailyChallenge.week_key(_unix(2026, 10, 11)) == "20261005", "Monday through Sunday share a week key")
	check(DailyChallenge.week_key(_unix(2026, 10, 12)) == "20261012" and DailyChallenge.week_key(_unix(2026, 1, 1)) == "20251229", "weeks roll over on Monday, also across years")
	var a := DailyChallenge.for_week("20261005")
	check(JSON.stringify(a) == JSON.stringify(DailyChallenge.for_week("20261005")) and DailyChallenge.is_weekly(a), "a week always gives the same challenge")
	var decks := {}
	var legal := true
	for week in 40:
		var key := DailyChallenge.week_key(_unix(2026, 1, 5) + week * 7 * 86400)
		var challenge := DailyChallenge.for_week(key)
		decks[",".join(PackedStringArray(challenge.units))] = true
		var ids: Array = challenge.modifiers
		legal = legal and ids.size() == 2 and ids[0] != ids[1] and not DailyChallenge.modifier_info(String(ids[0])).is_empty() and not DailyChallenge.modifier_info(String(ids[1])).is_empty()
		legal = legal and int(challenge.stage) >= DailyChallenge.WEEKLY_MIN_STAGE and int(challenge.stage) <= DailyChallenge.WEEKLY_MAX_STAGE
		legal = legal and BattleModel._valid_deck(challenge.units, BattleModel.UNIT_STATS) and BattleModel._valid_deck(challenge.structures, BattleModel.STRUCTURE_STATS)
	check(legal and decks.size() >= 15, "every week has legal decks, a tougher stage and two different twists (%d decks)" % decks.size())
	check(DailyChallenge.board_key(a) == "w20261005" and DailyChallenge.board_key(DailyChallenge.for_date("20261005")) == "20261005", "weekly boards are prefixed")

	var base := {"key": "20261005", "period": "weekly", "stage": 4, "units": ["shield", "swordsman", "archer"], "structures": ["wall", "swamp", "turret"], "modifier": "empty_hands", "modifiers": ["empty_hands", "fragile_base"]}
	var built := DailyChallenge.build(base)
	check(built.model.resources[0] == 20.0 and built.model.base_hp[0] == 300.0, "both twists apply")
	var elite := base.duplicate()
	elite.modifiers = ["rich_enemy", "elite_foe"]
	check(DailyChallenge.build(elite).stage == 6 and DailyChallenge.build(elite).model.resources[1] == BattleModel.MAX_RESOURCE, "twists combine, elite foe still adds stages")

	var save := SaveData.default_data()
	var result := DailyChallenge.record(save, base, true, 400.0, 90.0)
	check(result.new_best and save.weekly.has("20261005") and save.daily.is_empty() and save.stats.weekly_completed == 1 and save.stats.daily_completed == 0, "weekly results live in their own store")
	check(DailyChallenge.result_note(base, save, true).begins_with("주간 도전 성공") and DailyChallenge.result_note(base, save, false).contains("이번 주"), "result notes name the week")
	var stored := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(stored.weekly.has("20261005") and stored.stats.weekly_completed == 1, "weekly history survives saving")

	# Leaderboard keys.
	var board := ServerDailyBoard.new()
	var today := "20261008"
	var id := "e".repeat(32)
	check(board.submit("w20261005", id, "나", 1000, 80.0, today) and board.submit("w20260928", id, "나", 900, 80.0, today), "this week and last week can be submitted")
	check(not board.submit("w20260921", id, "나", 900, 80.0, today) and not board.submit("w20261012", id, "나", 900, 80.0, today) and not board.submit("w20261006", id, "나", 900, 80.0, today), "older, future and non-Monday weeks are refused")
	check(board.board("w20261005", id).rank == 1 and board.board("20261005", id).entries.is_empty(), "weekly and daily boards are separate")
	check(ServerDailyBoard.valid_date("w20261005") and ServerDailyBoard.valid_date("20261005") and not ServerDailyBoard.valid_date("x20261005") and not ServerDailyBoard.valid_date("w2026"), "board keys are validated")

	# UI flow.
	BattleReplay.save_dir = "user://weekly_challenge_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	check(main.find_child("WeeklyButton", true, false) != null, "the main menu offers the weekly challenge")
	main._show_daily_brief("weekly")
	await process_frame
	check(main.find_child("DailyModifier", true, false).text.contains("\n") and main.find_child("DailyDeck", true, false).get_child_count() == 3, "the brief shows two twists and the deck")
	main.find_child("StartDailyChallenge", true, false).pressed.emit()
	await process_frame
	check(DailyChallenge.is_weekly(main.daily_challenge) and main.daily_challenge.key == DailyChallenge.week_key(), "starting begins the current weekly challenge")
	main.set_process(false)
	for i in 120:
		main._process(0.1)
	main.local_model.winner = 0
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	await process_frame
	check(main.save_data.weekly.has(DailyChallenge.week_key()) and main.save_data.weekly[DailyChallenge.week_key()].won and main.save_data.daily.is_empty(), "the win is stored as a weekly result")
	check(main.save_data.achievements.has("weekly_clear") and main.save_data.achievements.has("daily_clear"), "the weekly badge unlocks")
	check(main.save_data.stats.ai_matches == 0, "weekly battles are not ordinary AI matches")
	var replay := BattleReplay.load_file(main.last_replay_path)
	check(not replay.is_empty() and replay.meta.period == "weekly" and bool(BattleReplay.verify(replay).ok), "the replay verifies and remembers it was weekly")
	check(load("res://scripts/screens/ReplayScreens.gd").describe(replay).title.begins_with("주간 도전"), "the list names it as a weekly challenge")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://weekly_challenge_test")
	print("weekly_challenge_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
