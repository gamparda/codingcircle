extends SceneTree
# Server player data without the network: daily backups and restoring a damaged store, the account session
# index and ranked records, cloud saves (compare-and-swap), report limits and Elo ratings.
const ServerBackup = preload("res://scripts/ServerBackup.gd")
const AccountStore = preload("res://scripts/accounts/AccountStore.gd")
const CloudSaves = preload("res://scripts/accounts/CloudSaves.gd")
const ReportLog = preload("res://scripts/accounts/ReportLog.gd")
const Rating = preload("res://scripts/accounts/Rating.gd")

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func _initialize() -> void:
	var dir := "user://player_data_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	var day := 86400
	var now := 1_800_000_000

	# Accounts: create, session index, ranked records.
	var store := AccountStore.new()
	store.configure(dir)
	var alice := String(store.create("google-a", "마왕", now).id)
	var bob := String(store.create("google-b", "용사", now).id)
	var token := store.issue_session(alice, now)
	check(store.resume(token, now + 10) == alice and store.by_session.size() == 1, "sessions resume through the index")
	check(store.profile(alice).rating == AccountStore.START_RATING, "new accounts start at the base rating")
	store.record_ranked(alice, 1024, "wins")
	store.record_ranked(bob, 976, "losses")
	var board := store.leaderboard(20)
	check(board.size() == 2 and board[0].nickname == "마왕" and board[0].wins == 1 and board[1].losses == 1, "the leaderboard ranks accounts that played")
	check(store.flush(), "accounts are written")

	# Backup today, then damage the store: it is restored, never replaced by an empty one.
	var copy := ServerBackup.snapshot(dir, now)
	check(not copy.is_empty() and FileAccess.file_exists(copy.path_join("accounts.json")), "a daily backup copies the account store")
	check(ServerBackup.snapshot(dir, now + 60).is_empty(), "one backup per day")
	var damaged := FileAccess.open(dir.path_join("accounts.json"), FileAccess.WRITE)
	damaged.store_string("{ broken")
	damaged.close()
	var reopened := AccountStore.new()
	reopened.configure(dir)
	check(reopened.accounts.has(alice) and reopened.profile(alice).rating == 1024 and reopened.resume(token, now + 20) == alice, "a damaged account store is restored from the backup")
	var kept := Array(DirAccess.get_files_at(dir)).filter(func(file): return String(file).begins_with("accounts.json.corrupt-"))
	check(kept.size() == 1, "the damaged file is kept for inspection")
	for offset in range(1, ServerBackup.KEEP_DAYS + 3):
		ServerBackup.snapshot(dir, now + offset * day)
	check(ServerBackup.days(dir).size() == ServerBackup.KEEP_DAYS, "old backups are pruned")

	# Cloud saves: compare-and-swap on the revision.
	var cloud := CloudSaves.new()
	cloud.configure(dir)
	check(cloud.read(alice).revision == 0, "no cloud save yet")
	var first := cloud.write(alice, 0, "{\"a\":1}", now)
	check(first.ok and first.revision == 1, "the first save is revision 1")
	var stale := cloud.write(alice, 0, "{\"a\":2}", now)
	check(not stale.ok and stale.error == "conflict" and stale.revision == 1, "a save based on an old revision is refused")
	check(cloud.write(alice, 1, "{\"a\":2}", now).revision == 2 and cloud.read(alice).data == "{\"a\":2}", "a save on the current revision replaces it")
	check(cloud.write(alice, 2, "not json", now).error == "invalid", "only JSON objects are stored")
	check(cloud.write(alice, 2, "{\"x\":\"%s\"}" % "a".repeat(CloudSaves.MAX_BYTES), now).error == "too_large", "oversized saves are refused")
	check(DirAccess.dir_exists_absolute(dir.path_join("saves").path_join(alice.substr(0, 2))), "saves are spread over folders by account")
	cloud.delete(alice)
	check(cloud.read(alice).revision == 0, "deleting the account deletes its save")

	# Reports.
	var reports := ReportLog.new()
	reports.configure(dir)
	var target := {"account": bob, "nickname": "용사"}
	check(reports.add(alice, target, "m1", "manner", now) == "", "a report is stored")
	check(reports.add(alice, target, "m1", "cheat", now) == "already_reported", "one report per match")
	check(reports.add(alice, target, "m2", "spam", now) == "invalid_reason", "unknown reasons are refused")
	for index in ReportLog.DAILY_LIMIT - 1:
		reports.add(alice, target, "n%d" % index, "nickname", now)
	check(reports.add(alice, target, "late", "nickname", now) == "limit", "reports are limited per day")
	check(reports.add(alice, target, "next-day", "nickname", now + day) == "", "the limit resets the next day")
	var lines := FileAccess.get_file_as_string(dir.path_join("reports.jsonl")).strip_edges().split("\n")
	check(lines.size() == ReportLog.DAILY_LIMIT + 1 and JSON.parse_string(lines[0]).target_nickname == "용사", "reports are appended one per line")

	# Elo.
	check(Rating.updated(1000, 1000, 1.0, 20) == 1016 and Rating.updated(1000, 1000, 0.0, 20) == 984, "an even game moves 16 points")
	check(Rating.updated(1000, 1000, 1.0, 0) == 1024, "new players move faster")
	check(Rating.updated(1000, 1400, 0.5, 20) > 1000, "a draw against a stronger player gains points")

	ServerBackup._remove_tree(dir)
	if failures == 0: print("PASS: %d player data checks" % checks)
	quit(1 if failures else 0)
