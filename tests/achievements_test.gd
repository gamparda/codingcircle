extends SceneTree
## Achievement rules, win streaks, save persistence, the gallery screen and the result-screen toast.

const Achievements = preload("res://scripts/Achievements.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _ids(list: Array) -> Array:
	return list.map(func(entry): return String(entry.id))

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var save := SaveData.default_data()
	var base := {"mode": "campaign", "won": true, "seconds": 120.0, "own_base": 300.0, "own_base_max": 500.0, "structures_built": 1, "kills": 5, "curve": [], "own_side": 0}
	var first := _ids(Achievements.evaluate(save, base, 1000))
	check(first == ["first_win"], "an ordinary first win only unlocks the first-win badge: %s" % [first])
	check(Achievements.evaluate(save, base, 2000).is_empty(), "badges unlock only once")
	check(int(save.achievements.first_win) == 1000, "unlock time is stored")
	var flawless := base.duplicate()
	flawless.own_base = 500.0
	flawless.seconds = 50.0
	flawless.structures_built = 3
	flawless.kills = 31
	var got := _ids(Achievements.evaluate(save, flawless, 3000))
	for id in ["flawless", "speed_win", "architect", "slayer"]:
		check(got.has(id), "%s unlocks" % id)
	var comeback := base.duplicate()
	comeback.curve = [0.1, -0.2, -0.5, -0.4, -0.5, -0.4, -0.5, -0.4, 0.3, 0.6]
	check(_ids(Achievements.evaluate(save, comeback, 4000)).has("comeback"), "comeback after being far behind")
	var brief := base.duplicate()
	brief.curve = [0.1, -0.5, -0.5, 0.3, 0.6, 0.7]
	check(not _ids(Achievements.evaluate(SaveData.default_data(), brief, 1)).has("comeback"), "a short dip is not a comeback")
	var mirrored := base.duplicate()
	mirrored.own_side = 1
	mirrored.curve = [0.4, 0.5, 0.6, 0.5, 0.4, 0.5, 0.6] # blue ahead means red (me) was behind
	var other := SaveData.default_data()
	check(_ids(Achievements.evaluate(other, mirrored, 1)).has("comeback"), "comeback is judged from the player's side")
	var marathon := base.duplicate()
	marathon.seconds = 301.0
	check(_ids(Achievements.evaluate(save, marathon, 5000)).has("marathon"), "five-minute win")
	var loss := base.duplicate()
	loss.won = false
	var fresh := SaveData.default_data()
	check(Achievements.evaluate(fresh, loss, 1).is_empty(), "a loss earns nothing")
	var ghost := base.duplicate()
	ghost.mode = "ghost"
	var ghost_save := SaveData.default_data()
	check(_ids(Achievements.evaluate(ghost_save, ghost, 1)) == ["ghost_buster"], "ghost wins only earn the ghost badge")
	var daily := base.duplicate()
	daily.mode = "daily"
	check(_ids(Achievements.evaluate(SaveData.default_data(), daily, 1)).has("daily_clear"), "daily clear")
	# Streaks.
	var streak := SaveData.default_data()
	for i in 3:
		Achievements.record_outcome(streak, true, false)
	check(streak.stats.win_streak == 3 and streak.stats.best_streak == 3, "three wins in a row")
	Achievements.record_outcome(streak, false, false)
	check(streak.stats.win_streak == 3, "a draw keeps the streak")
	check(_ids(Achievements.evaluate(streak, loss, 1)).has("streak3"), "streak badge")
	Achievements.record_outcome(streak, false, true)
	check(streak.stats.win_streak == 0 and streak.stats.best_streak == 3, "a loss resets the streak but keeps the best")
	var veteran := SaveData.default_data()
	veteran.stats.online_completed = 10
	check(_ids(Achievements.evaluate(veteran, loss, 1)).has("veteran"), "ten online matches")
	var stars := SaveData.default_data()
	for record in stars.campaign_records:
		record.best_stars = 3
	check(_ids(Achievements.evaluate(stars, loss, 1)).has("star_collector"), "all campaign stars")
	# Persistence through sanitize / JSON, with junk ignored.
	var stored := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(stored.achievements.has("first_win") and stored.achievements.has("flawless"), "achievements survive a save round trip")
	var junk := SaveData.sanitize({"achievements": {"first_win": "yes", "not_a_badge": 5, "flawless": 7}, "daily": {"x": 1, "20261008": {"score": 900, "won": true, "seconds": 80.0}}})
	check(not junk.achievements.has("first_win") and not junk.achievements.has("not_a_badge") and junk.achievements.flawless == 7, "junk entries are dropped")
	check(junk.daily.has("20261008") and not junk.daily.has("x"), "daily history keeps valid days only")
	check(Achievements.ids().size() == Achievements.DEFS.size() and Achievements.ids().size() == Array(Achievements.ids()).size(), "badge ids exist")

	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.achievements = {"first_win": 1760000000}
	main._build_records_screen()
	await process_frame
	check(main.find_child("AchievementsButton", true, false).text.contains("1 / %d" % Achievements.DEFS.size()), "records screen links to the gallery with a counter")
	main._build_achievements_screen()
	await process_frame
	var cards = main.find_child("AchievementGrid", true, false)
	check(cards.get_child_count() == Achievements.DEFS.size(), "one card per achievement")
	main.find_child("AchievementsBack", true, false).pressed.emit()
	await process_frame
	check(main.find_child("RecordsScreen", true, false) != null, "back returns to the record screen")

	# A real win through the result screen unlocks badges and shows the toast.
	main.save_data = SaveData.default_data()
	main.campaign_mode = true
	main.save_data.tutorial_completed = true
	main._start_local_ai_battle(1)
	main.set_process(false)
	main.local_model.winner = 0
	main.local_model.elapsed = 40.0
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	await process_frame
	check(main.save_data.achievements.has("first_win") and main.save_data.achievements.has("flawless") and main.save_data.achievements.has("speed_win"), "a quick flawless win unlocks three badges")
	check(main.result_overlay.find_child("AchievementToast", true, false) != null, "the result screen announces them")
	check(main.save_data.stats.win_streak == 1, "the streak counts")
	print("achievements_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
