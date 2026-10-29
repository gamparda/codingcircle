extends SceneTree
# Ranked seasons (monthly, ratings move halfway back, past seasons archived) and ranked card statistics.
const AccountStore = preload("res://scripts/accounts/AccountStore.gd")
const RankedStats = preload("res://scripts/accounts/RankedStats.gd")
const RankedFlow = preload("res://scripts/net/RankedFlow.gd")

const OCTOBER := 1793404800 # 2026-10-31 00:00 UTC
const NOVEMBER := 1793491200 # 2026-11-01 00:00 UTC

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var directory := "user://ranked_season_test_%d" % Time.get_ticks_usec()
	check(AccountStore.season_id(OCTOBER) == "2026-10" and AccountStore.season_id(NOVEMBER) == "2026-11", "seasons follow the UTC calendar month")
	check(AccountStore.valid_season("2026-12") and not AccountStore.valid_season("2026-13") and not AccountStore.valid_season("26-10") and not AccountStore.valid_season(202610), "season ids are validated")

	var store := AccountStore.new()
	store.now_override = OCTOBER
	store.configure(directory)
	var made: Dictionary = store.create("google-a", "용사", OCTOBER)
	var id := String(made.get("id", store.find_by_subject("google-a")))
	var other := String(store.create("google-b", "마왕", OCTOBER).get("id", store.find_by_subject("google-b")))
	store.record_ranked(id, 1200, "wins")
	store.record_ranked(id, 1180, "losses")
	store.record_ranked(other, 900, "losses")
	var profile := store.profile(id)
	check(profile.season == "2026-10" and profile.rating == 1180 and profile.best == 1200 and profile.ranked.wins == 1 and profile.ranked.losses == 1, "the season keeps its best rating")
	check(store.leaderboard(5).size() == 2, "both players are on this season's board")

	store.now_override = NOVEMBER
	check(store.leaderboard(5).is_empty(), "a new season starts with an empty board")
	profile = store.profile(id)
	check(profile.season == "2026-11" and profile.rating == 1090 and profile.best == 1090 and profile.ranked.wins == 0 and profile.ranked.losses == 0, "a new season moves the rating halfway back to 1000 and resets the record")
	check(profile.history.get("2026-10", {}) == {"rating": 1180, "best": 1200, "wins": 1, "losses": 1, "draws": 0}, "the finished season is archived")
	store.record_ranked(other, 980, "wins")
	check(int(store.profile(other).rating) == 980 and store.profile(other).history.has("2026-10") and store.leaderboard(5).size() == 1, "results count in the new season")
	store.flush()

	var reloaded := AccountStore.new()
	reloaded.now_override = NOVEMBER
	reloaded.configure(directory)
	check(reloaded.profile(id).history.has("2026-10") and reloaded.profile(id).season == "2026-11", "seasons survive a restart")
	var legacy := AccountStore.new()
	legacy.now_override = NOVEMBER
	var raw := {"subject": "a".repeat(64), "nickname": "옛날", "created": 1, "last_login": 1, "sessions": {}, "rating": 1300, "ranked": {"wins": 3, "losses": 0, "draws": 0}}
	legacy._adopt("b".repeat(32), raw)
	check(legacy.profile("b".repeat(32)).season == "2026-11" and legacy.profile("b".repeat(32)).rating == 1300, "accounts from before seasons join the current one unchanged")
	raw["season"] = "2026-10"; raw["history"] = {"2099-01": {"rating": 1, "best": 1, "wins": 0, "losses": 0, "draws": 0}, "2026-13": {}}
	legacy = AccountStore.new(); legacy.now_override = NOVEMBER
	legacy._adopt("c".repeat(32), raw)
	check(legacy.accounts["c".repeat(32)].history.is_empty(), "invalid or future seasons in a stored history are dropped")
	var history := {}
	for month in range(1, 13):
		for year in [2027, 2028, 2029]:
			history["%d-%02d" % [year, month]] = {}
	AccountStore._trim_history(history)
	check(history.size() == AccountStore.SEASON_HISTORY and history.has("2029-12") and not history.has("2027-12"), "only the newest seasons are kept")

	# Card statistics.
	var stats := RankedStats.new()
	stats.configure(directory, "2026-11", "test")
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer", "healer"], ["wall", "swamp", "turret", "generator"])
	model.configure_deck(1, ["berserker", "warlock", "necromancer", "archer"], ["wall", "lightning", "fireball", "generator"])
	model.banned = [["healer"], ["necromancer"]]
	stats.record(model, 0, "2026-11")
	stats.record(model, 2, "2026-11")
	var rows := {}
	for row in stats.summary():
		rows[row.kind] = row
	check(int(stats.data.matches) == 2 and rows.archer.picks == 4 and rows.archer.wins == 1 and rows.archer.draws == 2, "a card in both decks counts for each deck")
	check(rows.healer.picks == 2 and rows.healer.bans == 2 and rows.healer.wins == 1 and rows.necromancer.bans == 2 and rows.necromancer.wins == 0, "bans and wins are counted per card")
	check(stats.flush() and FileAccess.file_exists(directory.path_join("ranked_cards_2026-11_test.json")), "statistics are saved per season and ruleset")
	var again := RankedStats.new()
	again.configure(directory, "2026-11", "test")
	check(again.summary() == stats.summary(), "statistics survive a restart")
	again.record(model, 1, "2026-12")
	check(again.season == "2026-12" and int(again.data.matches) == 1 and FileAccess.file_exists(directory.path_join("ranked_cards_2026-11_test.json")), "a new season starts a new statistics file")
	check(RankedStats._sanitize({"matches": 3, "cards": {"intruder": {"picks": 1, "bans": 0, "wins": 0, "draws": 0}, "wall": {"picks": -1}}}).cards.is_empty(), "malformed stored cards are dropped")

	# The profile message.
	var data := {"rating": 1090, "wins": 0, "losses": 0, "draws": 0, "rank": 0, "leaderboard": [], "season": "2026-11", "best": 1090,
		"history": [{"season": "2026-10", "rating": 1180, "best": 1200, "wins": 1, "losses": 1, "draws": 0}], "cards": stats.summary(), "card_matches": 2}
	check(RankedFlow.valid_profile(data), "a full profile is accepted")
	var bad := data.duplicate(true); bad.cards[0].kind = "intruder"
	check(not RankedFlow.valid_profile(bad), "unknown cards are refused")
	bad = data.duplicate(true); bad.history[0].erase("best")
	check(not RankedFlow.valid_profile(bad), "incomplete seasons are refused")
	bad = data.duplicate(true); bad.erase("season")
	check(not RankedFlow.valid_profile(bad), "a profile without its season is refused")

	check(preload("res://scripts/screens/RankedBoard.gd").season_name("2026-11") == "2026년 11월", "seasons are named by year and month")
	preload("res://scripts/ServerBackup.gd")._remove_tree(directory)
	print("ranked_season_test failures=%d" % failures)
	quit(1 if failures else 0)
