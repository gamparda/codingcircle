extends SceneTree
## Community statistics: server aggregation, the daily board, the opt-in client queue and the screens that show them.

const ServerStats = preload("res://scripts/ServerStats.gd")
const ServerDailyBoard = preload("res://scripts/ServerDailyBoard.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

class ReportConnection:
	var online := true
	var sent: Array = []
	func client_is_online() -> bool: return online
	func send_confirmed_report(id, sequence, units, structures, result, mode, ruleset) -> void:
		sent.append([id, sequence, units, structures, result, mode, ruleset])
	func send_daily_score(date, id, nickname, score, seconds, ruleset) -> void:
		sent.append([date, id, nickname, score, seconds, ruleset])

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
	check(ServerStats.ruleset_id() == build.version and ServerStats.ruleset_id() != "0", "statistics use the content version generated in build_info.json")
	var dir := "user://community_stats_test"
	DirAccess.make_dir_recursive_absolute(dir)
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))

	# Aggregation.
	var stats := ServerStats.new()
	stats.configure(dir, "t1")
	var deck_a := ["shield", "swordsman", "archer", "healer"]
	var deck_b := ["archer", "shield", "swordsman", "healer"]
	var structures := ["wall", "swamp", "turret", "generator"]
	check(stats.record("online", deck_a, structures, 0) and stats.record("online", deck_b, structures, 1), "valid results are recorded; deck order does not matter")
	check(not stats.record("online", ["shield", "shield", "archer"], structures, 0) and not stats.record("online", deck_a, structures, 7) and not stats.record("nope", deck_a, structures, 0), "bad decks, results and sources are rejected")
	var snap := stats.snapshot([deck_a])
	var key := ServerStats.deck_key(deck_a)
	check(snap.online.matches == 2 and snap.online.lookup[key].games == 2 and snap.online.lookup[key].wins == 1, "the lookup returns the exact deck even with a small sample")
	check(snap.online.top.is_empty() and snap.reported.matches == 0, "small samples never reach the top list; sources stay apart")
	for i in ServerStats.MIN_SAMPLES:
		stats.record("online", ["berserker", "warlock", "necromancer", "healer"], structures, 0)
		stats.record("online", ["healer", "archer", "swordsman", "paladin"], structures, 1 if i % 2 == 0 else 0)
	var top: Array = stats.snapshot().online.top
	check(top.size() == 2 and ServerStats.deck_key(top[0].deck) == ServerStats.deck_key(["berserker", "warlock", "necromancer", "healer"]), "well-sampled decks are ranked by confidence")
	check(ServerStats.wilson_lower(3, 3) < ServerStats.wilson_lower(60, 100) and ServerStats.wilson_lower(0, 0) == 0.0, "a lucky tiny sample cannot outrank a big solid one")
	var model := BattleModel.new()
	model.configure_deck(0, deck_a, structures)
	model.configure_deck(1, ["healer", "archer", "swordsman", "paladin"], structures)
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
	var unversioned_path := dir.path_join("stats_0.json")
	ServerStats.write_json(unversioned_path, stats.data)
	var unversioned_bytes := FileAccess.get_file_as_bytes(unversioned_path)
	var current_store := ServerStats.new()
	current_store.configure(dir)
	check(current_store.path == dir.path_join("stats_%s.json" % build.version) and current_store.data.online.matches == 0 and FileAccess.get_file_as_bytes(unversioned_path) == unversioned_bytes, "default configuration uses a versioned store and preserves historical stats_0 bytes without merging them")
	check(not FileAccess.file_exists(dir.path_join("stats_t1.json.tmp")), "no temporary file is left behind")
	# Malformed persisted fields must not abort loading, querying or recording new results.
	var damaged_stats := stats.data.duplicate(true)
	damaged_stats.online.units.archer = {"games": [], "wins": {}, "draws": "0"}
	damaged_stats.online.units.shield = {"games": 2.5, "wins": 1, "draws": 0}
	damaged_stats.online.units.swordsman = {"games": 3, "wins": 2, "draws": 2}
	damaged_stats.online.combos["unknown,shield,swordsman"] = {"games": 100, "wins": 100, "draws": 0}
	damaged_stats.reported.matches = {}
	check(ServerStats.write_json(dir.path_join("stats_damaged.json"), damaged_stats), "damaged statistics fixture is written")
	var repaired := ServerStats.new()
	repaired.configure(dir, "damaged")
	check(repaired.data.online.matches == stats.data.online.matches and repaired.snapshot([deck_a]).online.lookup[key].games == 3 and repaired.data.reported.matches == 0, "valid statistics survive mixed malformed fields and JSON float counts")
	check(not repaired.data.online.units.has("archer") and not repaired.data.online.units.has("shield") and not repaired.data.online.units.has("swordsman") and not repaired.data.online.combos.has("unknown,shield,swordsman"), "invalid counts and unknown decks are omitted")
	check(repaired.record("online", deck_a, structures, 0) and repaired.data.online.units.archer.games == 1, "new results can update a repaired store")
	check(not ServerStats.valid_count(INF) and not ServerStats.valid_count(NAN) and not ServerStats.valid_count(true) and not ServerStats.valid_count("2") and not ServerStats.valid_count(-1) and not ServerStats.valid_count(1e20), "counts reject non-finite, coercible and out-of-range values")

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
	board.submit(today, rival, "상대", 1500, 60.0, today)
	check(board.board(today, me).rank == 1, "time orders equal scores")
	board.submit(today, rival, "새 이름", 1500, 40.0, today)
	check(board.board(today, rival).rank == 1 and board.board(today).entries[0].seconds == 40.0, "a faster equal-score retry changes the ranking")
	board.submit(today, rival, "최신 이름", 1500, 70.0, today)
	check(board.board(today).entries[0].seconds == 40.0 and board.board(today).entries[0].nick == "최신 이름", "slower ties retain the best time but refresh the nickname")
	var rejecting := ServerDailyBoard.new()
	rejecting.verifier = func(_date, entry): return int(entry.score) < 1000
	check(rejecting.submit(today, me, "나", 900, 50.0, today) and not rejecting.submit(today, rival, "상대", 1500, 50.0, today), "a verifier can veto submissions later")
	board.submit("20261030", me, "나", 900, 80.0, "20261030")
	check(not board.days.has("20261007"), "old days are pruned")
	var reloaded_board := ServerDailyBoard.new()
	reloaded_board.configure(dir)
	check(reloaded_board.days.has("20261030"), "the board survives a restart")
	var legacy_path := dir.path_join("daily_board.json")
	check(ServerStats.write_json(legacy_path, board.days), "legacy board fixture is written")
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path)
	var previous_board_bytes := FileAccess.get_file_as_bytes(board.path)
	var new_board := ServerDailyBoard.new()
	new_board.configure(dir, "new-board-rules")
	check(new_board.days.is_empty() and new_board.path != board.path, "new rules start an independent daily and weekly leaderboard")
	new_board.submit(today, me, "새 규칙", 200, 100.0, today)
	check(FileAccess.get_file_as_bytes(legacy_path) == legacy_bytes and FileAccess.get_file_as_bytes(board.path) == previous_board_bytes and board.board("20261030", me).mine == 900, "new-version writes preserve legacy and previous-version leaderboard data")
	var reopened_new := ServerDailyBoard.new()
	reopened_new.configure(dir, "new-board-rules")
	check(reopened_new.board(today, me).mine == 200 and reopened_new.board(today).ruleset == "new-board-rules", "new-version scores and board identity persist independently")
	var damaged_days := {today: {me: {"nick": " 나 ", "score": 900, "seconds": 80.0}, rival: 7,
		"c".repeat(32): {"nick": "상대", "score": 1000.5, "seconds": 60},
		"d".repeat(32): {"nick": "상대", "score": 1000, "seconds": []},
		"f".repeat(32): {"nick": "상대\n", "score": 1000, "seconds": 60},
		"bad-id": {"nick": "상대", "score": 1000, "seconds": 60}}, "20260230": {}, "w20261006": {}, "20261007": []}
	check(ServerStats.write_json(board.path, damaged_days), "damaged board fixture is written")
	var repaired_board := ServerDailyBoard.new()
	repaired_board.configure(dir)
	check(repaired_board.days.size() == 1 and repaired_board.board(today, me).total == 1 and repaired_board.board(today, me).mine == 900 and repaired_board.board(today).entries[0].nick == "나", "board loading preserves valid entries and excludes malformed ids, dates and scores")
	check(repaired_board.submit(today, rival, "복구", 1200, 60.0, today) and repaired_board.board(today, rival).rank == 1, "a previously malformed participant can submit again")
	check(ServerDailyBoard.valid_date("20240229") and not ServerDailyBoard.valid_date("20260229") and not ServerDailyBoard.valid_date("20261301") and not ServerDailyBoard.valid_date("+0261008"), "challenge keys require real calendar dates")
	board.dirty = true
	board.flush() # Keep the normal store for the existing persistence-retry checks below.

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
	check(MetaStats.queue_daily(save, today, 1000, 70.0) and not MetaStats.queue_daily(save, today, 1000, 80.0) and save.pending_daily[today].seconds == 70.0, "offline equal-score retries retain the faster time")
	var id := MetaStats.install_id(save)
	check(ServerDailyBoard.valid_id(id) and MetaStats.install_id(save) == id, "the install id is stable and well-formed")
	var stored := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(stored.install_id == id and stored.pending_reports.size() == MetaStats.MAX_PENDING and stored.pending_daily[today].score == 1000 and stored.settings.share_results, "queue and opt-in survive saving")
	var junk := SaveData.sanitize({"install_id": "nope", "pending_reports": [{"units": ["a"], "structures": [], "result": 0, "mode": "campaign"}, 5], "pending_daily": {"date": "x"}})
	check(junk.install_id == "" and junk.pending_reports.is_empty() and junk.pending_daily.is_empty() and not junk.settings.share_results, "junk is dropped and sharing defaults to off")
	check(stored.pending_reports == save.pending_reports and stored.next_report_sequence == save.next_report_sequence, "pending report sequences survive JSON saving without being reissued")
	var legacy := save.duplicate(true)
	legacy.erase("next_report_sequence")
	for report in legacy.pending_reports:
		report.erase("sequence")
		report.erase("ruleset")
	legacy = SaveData.sanitize(legacy)
	check(legacy.pending_reports[0].sequence == 1 and legacy.pending_reports[-1].sequence == MetaStats.MAX_PENDING and legacy.next_report_sequence == MetaStats.MAX_PENDING + 1, "older queues receive ordered sequences and retain every valid result")
	var unknown_connection := ReportConnection.new()
	MetaStats.flush(legacy, unknown_connection)
	check(legacy.pending_reports[0].ruleset == "0" and unknown_connection.sent.all(func(payload): return payload.size() == 6), "a legacy result without a recorded version is never relabelled and sent as current")
	var versioned := save.duplicate(true)
	versioned.pending_daily = {}
	versioned.pending_reports[0].ruleset = "older"
	versioned.pending_reports[1].erase("ruleset")
	versioned.pending_reports[2].ruleset = {}
	versioned = SaveData.sanitize(JSON.parse_string(JSON.stringify(versioned)))
	check(versioned.pending_reports[0].ruleset == "older" and versioned.pending_reports[1].ruleset == "0" and versioned.pending_reports[2].ruleset == "0" and versioned.pending_reports[3].ruleset == build.version, "loading retains old versions and marks missing or malformed versions as unknown")
	var version_connection := ReportConnection.new()
	MetaStats.flush(versioned, version_connection)
	var current_sequence := int(versioned.pending_reports[3].sequence)
	check(version_connection.sent.size() == 1 and version_connection.sent[0][1] == current_sequence and version_connection.sent[0][6] == build.version, "older results do not mix into current statistics or block the first current result")
	check(not MetaStats.acknowledge_report(versioned, id, int(versioned.pending_reports[0].sequence)) and not MetaStats.acknowledge_report(versioned, id, int(versioned.pending_reports[4].sequence)), "old and out-of-order confirmations cannot remove retained reports")
	check(MetaStats.acknowledge_report(versioned, id, current_sequence) and versioned.pending_reports[0].ruleset == "older" and versioned.pending_reports[3].sequence == current_sequence + 1, "current confirmation removes its report while preserving older reports")
	check(MetaStats.sharing_status(versioned, false, false).contains("서버 연결 후") and MetaStats.sharing_status(versioned, true, true).contains("기기 저장") and MetaStats.sharing_status(versioned, true, false).contains("버전 미상 결과·점수 3개"), "sharing status distinguishes connection, profile writes and excluded versions")
	var connection := ReportConnection.new()
	var before_send := save.duplicate(true)
	MetaStats.flush(save, connection)
	var expected_sends := 1 + int(ServerDailyBoard.accepts_date(today, DailyChallenge.date_key()))
	check(save == before_send and connection.sent.size() == expected_sends, "sending retains the unconfirmed queue and sends only its oldest report")
	connection.online = false
	MetaStats.flush(save, connection)
	check(connection.sent.size() == expected_sends and save == before_send, "disconnection preserves queued results")
	var first_sequence := int(save.pending_reports[0].sequence)
	check(not MetaStats.acknowledge_report(save, "f".repeat(32), first_sequence) and not MetaStats.acknowledge_report(save, id, first_sequence + 1), "unrelated and out-of-order acknowledgements cannot erase a result")
	check(MetaStats.acknowledge_report(save, id, first_sequence) and not MetaStats.acknowledge_report(save, id, first_sequence) and save.pending_reports.size() == MetaStats.MAX_PENDING - 1, "only a matching acknowledgement removes a result, once")
	check(not MetaStats.acknowledge_daily(save, id, today, 1000, 90.0) and save.pending_daily[today].seconds == 70.0, "a delayed score acknowledgement preserves the faster queued result")
	check(MetaStats.acknowledge_daily(save, id, today, 1000, 70.0) and save.pending_daily.is_empty(), "a matching score acknowledgement clears its queue")
	check(not MetaStats.queue_daily(save, today, 0, 70.0) and not MetaStats.queue_daily(save, today, 1000, NAN), "invalid challenge scores cannot block the retry queue")
	var challenge_queue := SaveData.default_data()
	challenge_queue.settings.share_results = true
	var current_date := DailyChallenge.date_key()
	challenge_queue.pending_daily[current_date] = {"score": 2500, "seconds": 50.0, "ruleset": "older"}
	var old_queue_connection := ReportConnection.new()
	MetaStats.flush(challenge_queue, old_queue_connection)
	check(old_queue_connection.sent.is_empty() and MetaStats.sharing_status(challenge_queue, true, false).contains("결과·점수 1개"), "old challenge scores are retained and visibly excluded from transmission")
	check(MetaStats.queue_daily(challenge_queue, current_date, 200, 100.0) and challenge_queue.pending_daily[current_date].score == 200, "an older high score cannot block a lower current-version submission")
	check(not MetaStats.acknowledge_daily(challenge_queue, challenge_queue.install_id, current_date, 200, 100.0, "older") and challenge_queue.pending_daily.has(current_date), "a foreign-version receipt cannot clear the current challenge score")
	var loaded_queue := SaveData.sanitize(JSON.parse_string(JSON.stringify(challenge_queue)))
	check(loaded_queue.pending_daily[current_date].ruleset == build.version, "challenge queue versions survive saving")
	challenge_queue.pending_daily[current_date].erase("ruleset")
	loaded_queue = SaveData.sanitize(challenge_queue)
	check(loaded_queue.pending_daily[current_date].ruleset == "0", "legacy challenge queues remain version unknown")
	MetaStats.queue_daily(save, "20000101", 1000, 70.0)
	check(MetaStats.prune_daily(save) and save.pending_daily.is_empty(), "expired boards leave the retry queue")
	var tomorrow := DailyChallenge.date_key(DailyChallenge._to_unix(DailyChallenge.date_key()) + 86400)
	MetaStats.queue_daily(save, tomorrow, 1000, 70.0)
	check(not MetaStats.prune_daily(save) and save.pending_daily.has(tomorrow), "a future score is retained until its submission window opens")
	var receipts := ServerStats.new()
	receipts.configure(dir, "receipts")
	check(receipts.record_report(id, 1, deck_a, structures, 0) and receipts.data.reported.matches == 1, "confirmed reports persist their counters and sequence together")
	check(receipts.record_report(id, 1, deck_a, structures, 0) and receipts.data.reported.matches == 1, "a duplicate report is acknowledged without counting it twice")
	DirAccess.make_dir_absolute(receipts.path + ".tmp")
	check(not receipts.record_report(id, 2, deck_a, structures, 1) and receipts.dirty and receipts.data.reported.matches == 2, "a disk failure counts once in memory and withholds confirmation")
	check(not receipts.record_report(id, 2, deck_a, structures, 1) and receipts.data.reported.matches == 2, "retries during a disk failure do not duplicate counters")
	DirAccess.remove_absolute(receipts.path + ".tmp")
	check(receipts.record_report(id, 2, deck_a, structures, 1) and not receipts.dirty, "retries confirm the same report after storage recovers")
	var restarted := ServerStats.new()
	restarted.configure(dir, "receipts")
	check(restarted.record_report(id, 1, deck_a, structures, 0) and restarted.record_report(id, 2, deck_a, structures, 1) and restarted.data.reported.matches == 2, "lost acknowledgements cannot duplicate counters after server restart")
	check(not restarted.record_report("bad", 3, deck_a, structures, 0) and not restarted.record_report(id, 0, deck_a, structures, 0), "malformed report identities and sequences are rejected")
	var receipt_file: Dictionary = ServerStats.read_json(restarted.path)
	receipt_file.report_sequences["bad"] = 10
	receipt_file.report_sequences["f".repeat(32)] = {"sequence": 10}
	ServerStats.write_json(restarted.path, receipt_file)
	restarted.configure(dir, "receipts")
	check(restarted.report_sequences == {id: 2} and restarted.data.reported.matches == 2, "malformed receipt fields cannot interrupt loading valid counters and deduplication")
	# Capacity diagnoses a receipt limit separately from disk failures and battle admission.
	var capacity := ServerStats.new()
	capacity.configure("", "capacity-test")
	for index in ServerStats.MAX_REPORTERS - 1:
		capacity.report_sequences["%032x" % index] = 1
	check(capacity.report_capacity_status().used == ServerStats.MAX_REPORTERS - 1 and not capacity.report_capacity_status().new_installations_paused, "receipt diagnostics show space for the final new installation")
	var final_id := "f".repeat(32)
	check(capacity.record_report(final_id, 1, deck_a, structures, 0), "the last receipt slot still accepts a new installation")
	var full_status := capacity.report_capacity_status()
	check(full_status == {"ruleset": "capacity-test", "used": ServerStats.MAX_REPORTERS, "limit": ServerStats.MAX_REPORTERS, "new_installations_paused": true}, "full receipt diagnostics expose only aggregate usage, limit and ruleset")
	check(not capacity.record_report("e".repeat(32), 1, deck_a, structures, 0) and capacity.report_sequences.size() == ServerStats.MAX_REPORTERS, "capacity rejects a new installation without evicting existing receipts")
	check(capacity.record_report(final_id, 1, deck_a, structures, 0) and capacity.record_report(final_id, 2, deck_a, structures, 1) and capacity.data.reported.matches == 2, "existing installations and duplicate confirmations continue at capacity")
	check(capacity.record("online", deck_a, structures, 0), "online results are still counted at the receipt limit")
	capacity.path = dir.path_join("stats_capacity-test.json")
	check(capacity.flush(true), "a full receipt store can still persist its counters")
	var loaded_capacity := ServerStats.new()
	loaded_capacity.configure(dir, "capacity-test")
	check(loaded_capacity.report_capacity_status().new_installations_paused and loaded_capacity._report_capacity_full and loaded_capacity.record_report(final_id, 2, deck_a, structures, 1) and loaded_capacity.data.reported.matches == 2, "startup diagnoses a full persisted store and continues acknowledging existing receipts")
	loaded_capacity.configure("", "another-ruleset")
	check(not loaded_capacity.report_capacity_status().new_installations_paused and not loaded_capacity._report_capacity_full and capacity.report_sequences.size() == ServerStats.MAX_REPORTERS, "a different ruleset resets its own capacity without discarding the old store")
	capacity.path = ""

	# Snapshot validation and cache.
	MetaStats.cache_path = dir.path_join("cache.json")
	MetaStats.snapshot = {}
	check(not MetaStats.valid_snapshot({}) and not MetaStats.valid_snapshot("x") and MetaStats.valid_snapshot(snap), "snapshots are validated")
	var fresh := stats.snapshot([deck_a])
	fresh.ruleset = ServerStats.ruleset_id()
	MetaStats.store(fresh)
	var old_snapshot := fresh.duplicate(true)
	old_snapshot.ruleset = "older"
	old_snapshot.online.matches = 999
	MetaStats.store(old_snapshot)
	check(MetaStats.current().online.matches == fresh.online.matches, "a different server ruleset cannot replace current statistics")
	MetaStats.snapshot = {}
	check(MetaStats.deck_record(deck_b).games == 3, "the cache is read back and deck order does not matter")
	check(MetaStats.record_text(MetaStats.deck_record(deck_a)).contains("표본 부족") and MetaStats.record_text({}).contains("없음"), "small samples are labelled")
	check(MetaStats.valid_board(board.board(today, me)) and not MetaStats.valid_board({"date": 5}), "boards are validated")
	var bad_snapshot := fresh.duplicate(true)
	bad_snapshot.online.units.archer = {"games": "10", "wins": 9, "draws": 0}
	check(not MetaStats.valid_snapshot(bad_snapshot), "cache validation checks nested kind counts")
	bad_snapshot = fresh.duplicate(true)
	bad_snapshot.online.top[0].deck = ["archer", {}, "shield"]
	check(not MetaStats.valid_snapshot(bad_snapshot), "cache validation checks displayed deck rows")
	bad_snapshot = fresh.duplicate(true)
	bad_snapshot.online.matches = NAN
	check(not MetaStats.valid_snapshot(bad_snapshot), "snapshot counts must be finite")
	var bad_board := board.board("20261030", me)
	bad_board.entries[0].seconds = {}
	check(not MetaStats.valid_board(bad_board), "board validation checks displayed times")
	bad_board = board.board("20261030", me)
	bad_board.rank = "1"
	check(not MetaStats.valid_board(bad_board), "board validation checks the player's rank")
	MetaStats.store(bad_snapshot)
	check(MetaStats.deck_record(deck_a).games == 3, "malformed updates do not replace the valid cache")
	bad_snapshot.online.matches = {}
	ServerStats.write_json(MetaStats.cache_path, bad_snapshot)
	MetaStats.snapshot = {}
	check(MetaStats.current().is_empty() and MetaStats.kind_text("units", "archer") == "", "malformed disk caches are discarded before display")
	# Accumulated lookup requests stay readable after a restart and keep the newest decks.
	var kinds := BattleModel.UNIT_STATS.keys()
	var requested := 0
	var newest_deck: Array = []
	for a in kinds.size():
		for b in range(a + 1, kinds.size()):
			for c in range(b + 1, kinds.size() - 1):
				if requested > ServerStats.MAX_LOOKUP:
					break
				newest_deck = [kinds[a], kinds[b], kinds[c], kinds[kinds.size() - 1]]
				stats.record("online", newest_deck, structures, 0)
				var update := stats.snapshot([newest_deck])
				update.ruleset = ServerStats.ruleset_id()
				MetaStats.store(update)
				requested += 1
	check(MetaStats.current().online.lookup.size() == ServerStats.MAX_LOOKUP and MetaStats.valid_snapshot(MetaStats.current()), "accumulated lookups obey the cache validation limit")
	MetaStats.snapshot = {}
	check(not MetaStats.deck_record(newest_deck).is_empty(), "the newest lookup survives cache reload after more than twelve requests")
	var reset_stats := ServerStats.new()
	reset_stats.record("online", deck_a, structures, 0)
	MetaStats.store(reset_stats.snapshot([deck_a]))
	check(MetaStats.current().online.lookup.size() == 1 and MetaStats.deck_record(deck_a).games == 1 and MetaStats.deck_record(newest_deck).is_empty(), "a server counter reset discards stale accumulated lookups")

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
	# Idle servers flush pending stores even without another report or finished match.
	main.network.stats = stats
	main.network.daily_board = board
	DirAccess.make_dir_absolute(stats.path + ".tmp")
	DirAccess.make_dir_absolute(board.path + ".tmp")
	var stats_original := FileAccess.get_file_as_string(stats.path)
	var board_original := FileAccess.get_file_as_string(board.path)
	stats.record("online", deck_a, structures, 0)
	board.submit("20261030", me, "나", 1000, 70.0, "20261030")
	main.network.flush_persistence()
	check(main.network.pending_persistence_count() == 2 and not main._server_can_update(), "unsaved statistics and scores block an idle server restart")
	check(FileAccess.get_file_as_string(stats.path) == stats_original and FileAccess.get_file_as_string(board.path) == board_original, "failed server store writes preserve both original files")
	main.server_state_dir = dir
	main._update_server_lifecycle(1.0)
	var server_status: Dictionary = ServerStats.read_json(dir.path_join("server-status.json"))
	check(server_status.pending_saves == 2 and not server_status.safe_to_update, "server status exposes pending writes and postpones updates")
	check(server_status.accepting_matches and not server_status.replay_backlog_full and server_status.pending_replay_commands == 0, "status distinguishes ordinary pending statistics from replay backpressure")
	check(server_status.reported_result_capacity.ruleset == stats.ruleset and int(server_status.reported_result_capacity.used) == stats.report_sequences.size() and int(server_status.reported_result_capacity.limit) == ServerStats.MAX_REPORTERS and not server_status.reported_result_capacity.new_installations_paused, "server status includes receipt capacity independently of pending writes")
	main.network.stats = capacity
	main._update_server_lifecycle(1.0)
	server_status = ServerStats.read_json(dir.path_join("server-status.json"))
	check(server_status.reported_result_capacity.new_installations_paused and server_status.accepting_matches and server_status.pending_saves == 1, "receipt capacity does not pause battles or invent a pending disk write")
	main.network.stats = stats
	for index in main.network.replays.MAX_PENDING:
		main.network.replays.pending.append({"replay": {"commands": []}})
	main._update_server_lifecycle(1.0)
	server_status = ServerStats.read_json(dir.path_join("server-status.json"))
	check(server_status.accepting_players and not server_status.accepting_matches and server_status.replay_backlog_full and server_status.pending_saves == 18, "server status exposes storage admission pause separately from update draining")
	main.network.replays.pending.clear()
	main._update_server_lifecycle(1.0)
	var status_original := FileAccess.get_file_as_string(dir.path_join("server-status.json"))
	DirAccess.make_dir_absolute(dir.path_join("server-status.json.tmp"))
	main._update_server_lifecycle(1.0)
	check(FileAccess.get_file_as_string(dir.path_join("server-status.json")) == status_original, "failed status replacement preserves the previous status")
	DirAccess.remove_absolute(dir.path_join("server-status.json.tmp"))
	DirAccess.remove_absolute(stats.path + ".tmp")
	DirAccess.remove_absolute(board.path + ".tmp")
	main.network.persistence_elapsed = 0.0
	main.network._advance_persistence(NetworkController.PERSISTENCE_RETRY_SECONDS - 1.0)
	check(main.network.pending_persistence_count() == 2, "pending writes are not retried every frame")
	main.network._advance_persistence(1.0)
	var retry_stats := ServerStats.new()
	retry_stats.configure(dir, "t1")
	var retry_board := ServerDailyBoard.new()
	retry_board.configure(dir)
	check(main.network.pending_persistence_count() == 0 and main._server_can_update() and retry_stats.data.online.matches == stats.data.online.matches and retry_board.board("20261030", me).mine == 1000, "periodic retries recover both stores and release the update guard without new submissions")
	main.network.replays.pending.append({})
	check(not main._server_can_update(), "a pending replay alone blocks an otherwise idle server restart")
	main.network.replays.pending.clear()
	main.server_state_dir = ""
	var shown := ServerDailyBoard.new()
	shown.submit(DailyChallenge.date_key(), me, "나", 900, 80.0)
	shown.submit(DailyChallenge.date_key(), rival, "상대", 1200, 70.0)
	MetaStats.boards[DailyChallenge.date_key()] = shown.board(DailyChallenge.date_key(), me)
	main._show_daily_brief()
	await process_frame
	check(main.find_child("DailyBoardRows", true, false).get_child_count() >= 3, "the daily brief lists the board")
	var toggle: CheckButton = main.find_child("ShareResultsToggle", true, false)
	check(toggle != null and not toggle.button_pressed, "sharing is off by default")
	var sharing_label: Label = main.find_child("ResultSharingStatus", true, false)
	check(sharing_label != null and sharing_label.text == "결과 공유 꺼짐", "the sharing card shows its current transmission state")
	toggle.button_pressed = true
	check(main.save_data.settings.share_results, "the switch is stored")
	check(sharing_label.text == "전송 대기 없음", "the sharing status updates when the switch changes")
	MetaStats.queue_report(main.save_data, deck_a, structures, 0, "campaign")
	MetaStats.queue_daily(main.save_data, DailyChallenge.date_key(), 1000, 80.0)
	main._save_profile()
	var profile_id := String(main.save_data.install_id)
	var profile_sequence := int(main.save_data.pending_reports[0].sequence)
	main.network.result_report_saved.emit(profile_id, profile_sequence)
	main.network.daily_score_saved.emit(profile_id, DailyChallenge.date_key(), 1000, 80.0, ServerStats.ruleset_id())
	var confirmed_profile := SaveData.load_data()
	check(main.save_data.pending_reports.is_empty() and main.save_data.pending_daily.is_empty() and confirmed_profile.pending_reports.is_empty() and confirmed_profile.pending_daily.is_empty(), "Main persists both acknowledgements so restart does not resend confirmed results")
	check(main.result_sharing_elapsed == MetaStats.RETRY_SECONDS - 0.5, "a confirmed result schedules the next queued report without waiting a full retry period")
	MetaStats.queue_report(main.save_data, deck_a, structures, 0, "practice")
	await create_timer(1.05).timeout
	check(sharing_label.text.contains("전송 대기 1개"), "the open sharing card refreshes its pending count")
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
