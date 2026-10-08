extends SceneTree
## Community statistics: server aggregation, the daily board, the opt-in client queue and the screens that show them.

const ServerStats = preload("res://scripts/ServerStats.gd")
const ServerDailyBoard = preload("res://scripts/ServerDailyBoard.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var dir := "user://community_stats_test"
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))

	# Aggregation.
	var stats := ServerStats.new()
	stats.configure(dir, "t1")
	var deck_a := ["shield", "swordsman", "archer"]
	var deck_b := ["archer", "shield", "swordsman"]
	var structures := ["wall", "swamp", "turret"]
	check(stats.record("online", deck_a, structures, 0) and stats.record("online", deck_b, structures, 1), "valid results are recorded; deck order does not matter")
	check(not stats.record("online", ["shield", "shield", "archer"], structures, 0) and not stats.record("online", deck_a, structures, 7) and not stats.record("nope", deck_a, structures, 0), "bad decks, results and sources are rejected")
	var snap := stats.snapshot([deck_a])
	var key := ServerStats.deck_key(deck_a)
	check(snap.online.matches == 2 and snap.online.lookup[key].games == 2 and snap.online.lookup[key].wins == 1, "the lookup returns the exact deck even with a small sample")
	check(snap.online.top.is_empty() and snap.reported.matches == 0, "small samples never reach the top list; sources stay apart")
	for i in ServerStats.MIN_SAMPLES:
		stats.record("online", ["berserker", "warlock", "necromancer"], structures, 0)
		stats.record("online", ["healer", "archer", "swordsman"], structures, 1 if i % 2 == 0 else 0)
	var top: Array = stats.snapshot().online.top
	check(top.size() == 2 and ServerStats.deck_key(top[0].deck) == ServerStats.deck_key(["berserker", "warlock", "necromancer"]), "well-sampled decks are ranked by confidence")
	check(ServerStats.wilson_lower(3, 3) < ServerStats.wilson_lower(60, 100) and ServerStats.wilson_lower(0, 0) == 0.0, "a lucky tiny sample cannot outrank a big solid one")
	var model := BattleModel.new()
	model.configure_deck(0, deck_a, structures)
	model.configure_deck(1, ["healer", "archer", "swordsman"], structures)
	model.winner = 0
	var before: int = stats.data.online.matches
	stats.record_model(model)
	check(stats.data.online.matches == before + 2, "a finished match counts once per side")
	model.winner = -1
	stats.record_model(model)
	check(stats.data.online.matches == before + 2, "an unfinished match counts nothing")
	stats.flush(true)
	var reloaded := ServerStats.new()
	reloaded.configure(dir, "t1")
	check(reloaded.data.online.matches == stats.data.online.matches and FileAccess.file_exists(dir.path_join("stats_t1.json")), "statistics survive a restart")
	var other_rules := ServerStats.new()
	other_rules.configure(dir, "t2")
	check(other_rules.data.online.matches == 0, "a new ruleset starts from zero")
	check(not FileAccess.file_exists(dir.path_join("stats_t1.json.tmp")), "no temporary file is left behind")

	# Daily board.
	var board := ServerDailyBoard.new()
	board.configure(dir)
	var today := "20261008"
	var me := "a".repeat(32)
	var rival := "b".repeat(32)
	check(board.submit(today, me, "나", 900, 80.0, today) and board.submit(today, rival, "상대", 1200, 70.0, today), "valid scores are accepted")
	check(board.submit("20261007", me, "나", 500, 90.0, today), "yesterday can still be submitted")
	check(not board.submit("20261001", me, "나", 900, 80.0, today) and not board.submit("20261009", me, "나", 900, 80.0, today), "other days are rejected")
	check(not board.submit(today, "xyz", "나", 900, 80.0, today) and not board.submit(today, me, "", 900, 80.0, today) and not board.submit(today, me, "나", 99999, 80.0, today) and not board.submit(today, me, "나", 900, -5.0, today), "bad ids, names, scores and times are rejected")
	board.submit(today, me, "나", 700, 60.0, today)
	check(board.board(today, me).mine == 900, "a worse retry keeps the best score")
	board.submit(today, me, "나", 1500, 50.0, today)
	var view := board.board(today, me)
	check(view.rank == 1 and view.mine == 1500 and view.total == 2 and view.entries[0].nick == "나" and view.entries[1].nick == "상대", "the board is ordered by score")
	check(board.board(today, "c".repeat(32)).rank == 0, "a stranger has no rank")
	var rejecting := ServerDailyBoard.new()
	rejecting.verifier = func(_date, entry): return int(entry.score) < 1000
	check(rejecting.submit(today, me, "나", 900, 50.0, today) and not rejecting.submit(today, rival, "상대", 1500, 50.0, today), "a verifier can veto submissions later")
	board.submit("20261030", me, "나", 900, 80.0, "20261030")
	check(not board.days.has("20261007"), "old days are pruned")
	var reloaded_board := ServerDailyBoard.new()
	reloaded_board.configure(dir)
	check(reloaded_board.days.has("20261030"), "the board survives a restart")

	# Client queue and opt-in.
	var save := SaveData.default_data()
	check(not MetaStats.queue_report(save, deck_a, structures, 0, "campaign") and save.pending_reports.is_empty(), "nothing is queued without opting in")
	save.settings.share_results = true
	check(MetaStats.queue_report(save, deck_a, structures, 0, "campaign") and not MetaStats.queue_report(save, deck_a, structures, 0, "online"), "only solo modes are queued")
	for i in 30:
		MetaStats.queue_report(save, deck_a, structures, 1, "practice")
	check(save.pending_reports.size() == MetaStats.MAX_PENDING, "the queue is bounded")
	MetaStats.queue_daily(save, today, 900, 80.0)
	check(not MetaStats.queue_daily(save, today, 800, 60.0) and MetaStats.queue_daily(save, today, 1000, 90.0) and save.pending_daily[today].score == 1000, "only the best unsent daily score is kept")
	var id := MetaStats.install_id(save)
	check(ServerDailyBoard.valid_id(id) and MetaStats.install_id(save) == id, "the install id is stable and well-formed")
	var stored := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(stored.install_id == id and stored.pending_reports.size() == MetaStats.MAX_PENDING and stored.pending_daily[today].score == 1000 and stored.settings.share_results, "queue and opt-in survive saving")
	var junk := SaveData.sanitize({"install_id": "nope", "pending_reports": [{"units": ["a"], "structures": [], "result": 0, "mode": "campaign"}, 5], "pending_daily": {"date": "x"}})
	check(junk.install_id == "" and junk.pending_reports.is_empty() and junk.pending_daily.is_empty() and not junk.settings.share_results, "junk is dropped and sharing defaults to off")

	# Snapshot validation and cache.
	MetaStats.cache_path = dir.path_join("cache.json")
	MetaStats.snapshot = {}
	check(not MetaStats.valid_snapshot({}) and not MetaStats.valid_snapshot("x") and MetaStats.valid_snapshot(snap), "snapshots are validated")
	var fresh := stats.snapshot([deck_a])
	fresh.ruleset = ServerStats.ruleset_id()
	MetaStats.store(fresh)
	MetaStats.snapshot = {}
	check(MetaStats.deck_record(deck_b).games == 3, "the cache is read back and deck order does not matter")
	check(MetaStats.record_text(MetaStats.deck_record(deck_a)).contains("표본 부족") and MetaStats.record_text({}).contains("없음"), "small samples are labelled")
	check(MetaStats.valid_board(board.board(today, me)) and not MetaStats.valid_board({"date": 5}), "boards are validated")

	# Screens.
	BattleReplay.save_dir = "user://community_stats_test_replays"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	var shown := ServerDailyBoard.new()
	shown.submit(DailyChallenge.date_key(), me, "나", 900, 80.0)
	shown.submit(DailyChallenge.date_key(), rival, "상대", 1200, 70.0)
	MetaStats.boards[DailyChallenge.date_key()] = shown.board(DailyChallenge.date_key(), me)
	main._show_daily_brief()
	await process_frame
	check(main.find_child("DailyBoardRows", true, false).get_child_count() >= 3, "the daily brief lists the board")
	var toggle: CheckButton = main.find_child("ShareResultsToggle", true, false)
	check(toggle != null and not toggle.button_pressed, "sharing is off by default")
	toggle.button_pressed = true
	check(main.save_data.settings.share_results, "the switch is stored")
	main.network.daily_board_received.emit({"date": DailyChallenge.date_key(), "total": 0, "entries": [], "rank": 0, "mine": 0})
	await process_frame
	main._dismiss_action_overlay()
	load("res://scripts/screens/ReplayScreens.gd")._show_deck_analysis(main)
	await process_frame
	check(main.find_child("GlobalDeckStats", true, false) != null and main.find_child("ShareResultsToggle", true, false) != null, "deck analysis shows the community card and the switch")
	main.network.meta_stats_received.emit(MetaStats.current())
	await process_frame
	# Unit and structure statistics on the deck screen.
	var kind_snapshot := stats.snapshot()
	kind_snapshot.ruleset = ServerStats.ruleset_id()
	MetaStats.snapshot = {}
	MetaStats.store(kind_snapshot)
	var any_kind := "berserker"
	check(MetaStats.kind_text("units", any_kind).begins_with("선택 ") and MetaStats.kind_text("units", "nope") == "", "kind text shows pick and win rate, empty for unknown kinds")
	main._build_deck_screen()
	await process_frame
	var chips: Array = main.find_children("CommunityChip", "Label", true, false)
	check(chips.size() == BattleModel.UNIT_STATS.size() + BattleModel.STRUCTURE_STATS.size(), "every deck card has a community chip")
	check(chips.any(func(chip): return chip.text.begins_with("선택 ")), "chips show the statistics that were received")
	BattleReplay.save_dir = "user://replays"
	DirAccess.remove_absolute("user://community_stats_test_replays")
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	print("community_stats_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
