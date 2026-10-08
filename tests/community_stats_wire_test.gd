extends SceneTree
## Real client/server round trip for the community statistics, result reports and the daily board.

const MetaStats = preload("res://scripts/MetaStats.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
var server
var client
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	Engine.max_fps = 20
	call_deferred("run")

func make_controller(label: String):
	var holder := Node.new(); holder.name = label; get_root().add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	controller.set_room_request("session"); controller.client_nickname = label
	return controller

func wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	return predicate.call()

func finish(code: int) -> void:
	if is_instance_valid(client):
		client.disconnect_from_server(); await create_timer(0.2).timeout
	await create_timer(0.15).timeout
	if is_instance_valid(server): server.multiplayer.multiplayer_peer.close()
	print("community_stats_wire_test checks=%d failures=%d" % [checks, failures])
	quit(code)

func run() -> void:
	create_timer(30.0).timeout.connect(func(): printerr("community wire watchdog"); finish(1))
	MetaStats.cache_path = "user://community_wire_cache.json"
	MetaStats.snapshot = {}
	var port := 27987
	server = make_controller("StatsServer")
	if not server.start_dedicated_server(port):
		await finish(1); return
	server.configure_stats("")
	var deck := ["shield", "swordsman", "archer"]
	var structures := ["wall", "swamp", "turret"]
	for i in ServerStats.MIN_SAMPLES + 5:
		server.stats.record("online", deck, structures, 0 if i % 3 != 0 else 1)
	client = make_controller("클라")
	var received := []
	client.meta_stats_received.connect(func(data): received.append(data))
	var boards := []
	client.daily_board_received.connect(func(data): boards.append(data))
	client.connect_to_server("127.0.0.1", port)
	if not await wait_until(func(): return client.client_connection_state == "lobby"):
		check(false, "client reaches the lobby"); await finish(1); return
	client.send_stats_request([deck])
	check(await wait_until(func(): return not received.is_empty()), "the server answers a statistics request")
	check(not received.is_empty() and received[0].online.matches == ServerStats.MIN_SAMPLES + 5 and received[0].online.top.size() == 1, "the snapshot carries the aggregated games")
	check(MetaStats.deck_record(deck).games == ServerStats.MIN_SAMPLES + 5, "the client cached the answer")
	client.send_stats_request([["x", "y", "z"], "junk"])
	check(await wait_until(func(): return received.size() == 2), "malformed lookups are tolerated")

	client.send_result_report(deck, structures, 0, "campaign")
	check(await wait_until(func(): return server.stats.data.reported.matches == 1), "a reported result is counted in its own bucket")
	client.send_result_report(deck, structures, 0, "online")
	client.send_result_report(["bad"], structures, 0, "campaign")
	await create_timer(0.4).timeout
	check(server.stats.data.reported.matches == 1, "bad modes and decks are ignored")
	for i in NetworkController.MAX_REPORTS_PER_CONNECTION + 10:
		client.send_result_report(deck, structures, 1, "practice")
	await create_timer(0.8).timeout
	check(server.stats.data.reported.matches <= NetworkController.MAX_REPORTS_PER_CONNECTION, "one connection cannot flood the reports")

	var today := DailyChallenge.date_key()
	var id := "d".repeat(32)
	client.send_daily_score(today, id, "클라", 1100, 75.0)
	check(await wait_until(func(): return not boards.is_empty()), "a submitted score returns the board")
	check(boards[0].rank == 1 and boards[0].mine == 1100 and boards[0].entries[0].nick == "클라", "the player is first on an empty board")
	client.send_daily_score("20000101", id, "클라", 1500, 75.0)
	client.send_daily_score(today, "bad", "클라", 1500, 75.0)
	client.send_daily_score(today, id, "클라", 999999, 75.0)
	await create_timer(0.4).timeout
	check(server.daily_board.board(today, id).mine == 1100, "invalid submissions change nothing")
	client.send_daily_board_request(today, id)
	check(await wait_until(func(): return boards.size() >= 2), "the board can be requested")
	# Replay codes and recent online battles.
	var BattleReplay = load("res://scripts/BattleReplay.gd")
	var model := BattleModel.new()
	model.configure_deck(0, deck, structures)
	model.configure_deck(1, ["berserker", "warlock", "necromancer"], structures)
	server.replays.begin(77, model, {"mode": "room"})
	for tick in 90:
		if tick % 30 == 0 and model.spawn_unit(0, "swordsman"):
			server.replays.on_spawn(77, 0, "swordsman")
		model.tick(1.0 / 30.0)
		server.replays.on_tick(77)
	model.winner = 1
	server.replays.settle(77, model)
	for path in server.replays.saved_paths:
		DirAccess.remove_absolute(path)
	check(server.shelf.recent().size() == 1, "a finished online match is shelved automatically")
	var recents := []
	client.recent_replays_received.connect(func(list): recents.append(list))
	client.send_recent_request()
	check(await wait_until(func(): return not recents.is_empty()) and recents[0].size() == 1 and int(recents[0][0].winner) == 1, "the recent list reaches the client")
	var fetched := []
	client.shared_replay_received.connect(func(code, text): fetched.append([code, text]))
	client.send_replay_fetch(String(recents[0][0].code).to_lower())
	check(await wait_until(func(): return not fetched.is_empty()) and not BattleReplay.from_share_text(fetched[0][1]).is_empty(), "the replay can be fetched by code, in any letter case")
	var codes := []
	client.replay_code_received.connect(func(code): codes.append(code))
	var mine: String = BattleReplay.to_share_text(BattleReplay.make_clip(BattleReplay.from_share_text(fetched[0][1]), 45, "내 클립"))
	client.send_replay_upload(mine)
	check(await wait_until(func(): return not codes.is_empty()) and codes[0].length() == 6, "an upload answers with a code")
	check(server.shelf.recent().size() == 1, "uploads stay private")
	client.send_replay_upload("garbage")
	check(await wait_until(func(): return codes.size() == 2) and codes[1] == "", "bad uploads are refused")
	client.send_replay_fetch("ZZZZZZ")
	check(await wait_until(func(): return fetched.size() == 2) and fetched[1][1] == "", "unknown codes answer with nothing")
	DirAccess.remove_absolute("user://community_wire_cache.json")
	await finish(1 if failures > 0 else 0)

