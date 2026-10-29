extends SceneTree
# Ranked games, reports and cloud saves over real ENet/DTLS RPCs between signed-in accounts and a guest.
const AccountTest = preload("res://tests/account_test.gd")
const PORT := 27997

var checks := 0
var failures := 0
var key: CryptoKey
var events: Dictionary = {}

func _initialize() -> void:
	Engine.max_fps = 30
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func note(label: String, kind: String, value) -> void:
	events[label + ":" + kind] = value

func make_controller(label: String):
	var holder := Node.new(); holder.name = label; root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	controller.set_room_request("session"); controller.client_nickname = label
	controller.account_result_received.connect(func(result): note(label, "account", result))
	controller.account_nonce_received.connect(func(nonce): note(label, "nonce", nonce))
	controller.match_found.connect(func(side): note(label, "match", side))
	controller.ban_phase_started.connect(func(data): note(label, "ban", data))
	controller.ranked_result_received.connect(func(data): note(label, "ranked", data))
	controller.ranked_profile_received.connect(func(data): note(label, "profile", data))
	controller.report_result_received.connect(func(error): note(label, "report", error))
	controller.session_error.connect(func(text): note(label, "error", text))
	controller.cloud_save_received.connect(func(revision, text): note(label, "cloud", [revision, text]))
	controller.cloud_save_stored.connect(func(ok, revision, error): note(label, "stored", [ok, revision, error]))
	return controller

func wait_for(label: String, kind: String) -> Variant:
	var deadline := Time.get_ticks_msec() + 6000
	while not events.has(label + ":" + kind) and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	var value = events.get(label + ":" + kind)
	events.erase(label + ":" + kind)
	return value

func sign_up(client, label: String, nickname: String) -> void:
	client.account_request_nonce()
	var nonce = await wait_for(label, "nonce")
	client.account_sign_in(AccountTest.token(key, AccountTest.claims(String(nonce), int(Time.get_unix_time_from_system()), {"sub": "google-" + label})))
	await wait_for(label, "account")
	client.account_create(nickname)
	await wait_for(label, "account")

func run() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("ranked wire watchdog"); quit(1))
	key = Crypto.new().generate_rsa(2048)
	var directory := "user://ranked_wire_%d" % Time.get_ticks_usec()
	var server = make_controller("Server")
	if not server.start_dedicated_server(PORT): quit(1); return
	server.configure_accounts(directory, false)
	server.google.keys = {"test-key": key}
	var alice = make_controller("alice"); var bob = make_controller("bob"); var carol = make_controller("carol")
	alice.set_client_deck(["shield", "swordsman", "archer", "healer"], ["wall", "swamp", "turret", "generator"])
	bob.set_client_deck(["berserker", "warlock", "necromancer", "archer"], ["wall", "lightning", "fireball", "generator"])
	for client in [alice, bob, carol]: client.connect_to_server("127.0.0.1", PORT)
	var deadline := Time.get_ticks_msec() + 6000
	while [alice, bob, carol].any(func(client): return client.client_connection_state != "lobby") and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	for client in [alice, bob, carol]: client.client_transport_verified = true
	await sign_up(alice, "alice", "마왕")
	await sign_up(bob, "bob", "용사")
	check(server.peer_accounts.size() == 2, "two accounts are signed in")
	check(DirAccess.dir_exists_absolute(directory.path_join("backups")), "the server backs up its state when it starts")

	# A guest cannot queue for ranked.
	carol.start_ranked_match()
	check(String(await wait_for("carol", "error")).contains("로그인"), "guests are refused from ranked")

	# Ranked: both queue, each bans one of the other's cards, play, alice surrenders.
	alice.start_ranked_match(); bob.start_ranked_match()
	var alice_ban = await wait_for("alice", "ban")
	var bob_ban = await wait_for("bob", "ban")
	check(alice_ban is Dictionary and alice_ban.units.has("necromancer") and alice_ban.structures.has("lightning") and bob_ban is Dictionary and bob_ban.units.has("healer"), "each player is shown the other's deck to ban from")
	check(events.get("alice:match") == null, "the battle waits for the bans")
	var ban_room: String = String(server.sessions.peer_to_room.get(alice.multiplayer.get_unique_id(), ""))
	alice.send_ban("healer") # not in bob's deck: ignored
	alice.send_ban("necromancer")
	alice.send_ban("warlock") # only the first ban counts
	await create_timer(0.4).timeout
	check(server.ranked_bans.has(ban_room) and server.ranked_bans[ban_room].bans.values() == ["necromancer"] and events.get("alice:match") == null, "one ban is kept and the battle waits for the other player")
	server.ranked_bans[ban_room].deadline = 0 # bob never chooses: the time runs out
	check(await wait_for("alice", "match") != null and await wait_for("bob", "match") != null, "two accounts are paired for ranked once the ban time is over")
	var ranked_model = server.models.get(server.registry.get_match_id(alice.multiplayer.get_unique_id()))
	var bob_side: int = server.registry.get_side(bob.multiplayer.get_unique_id())
	check(not server.ranked_bans.has(ban_room) and ranked_model.banned[bob_side] == ["necromancer"] and ranked_model.banned[1 - bob_side].is_empty(), "a ban removes the chosen card from the opponent; no choice bans nothing")
	ranked_model.resources[bob_side] = 500.0
	check(not ranked_model.spawn_unit(bob_side, "necromancer") and ranked_model.spawn_unit(bob_side, "berserker"), "a banned card cannot be played; the rest of the deck can")
	check(alice.client_match_ranked and bob.client_match_ranked, "clients know the match is ranked")
	var room: Dictionary = server.sessions.room_for(alice.multiplayer.get_unique_id())
	var names: Array = room.members.values().map(func(member): return member.nickname)
	check(names.has("마왕") and names.has("용사") and not names.has("alice"), "ranked plays under the account nicknames")
	alice.send_surrender()
	var lost = await wait_for("alice", "ranked")
	var won = await wait_for("bob", "ranked")
	check(lost is Dictionary and lost.outcome == "losses" and int(lost.delta) < 0, "the loser's rating drops")
	check(won is Dictionary and won.outcome == "wins" and int(won.rating) == 1024, "the winner gains provisional points")
	check(server.accounts.leaderboard(5)[0].nickname == "용사", "the leaderboard follows ranked results")
	bob.send_ranked_profile_request()
	var profile = await wait_for("bob", "profile")
	check(profile is Dictionary and profile.rating == 1024 and profile.wins == 1 and profile.rank == 1 and profile.leaderboard.size() == 2, "a player sees their rating, rank and the leaderboard")
	var bob_cards := {}
	for row in profile.cards: bob_cards[row.kind] = row
	check(profile.season == server.accounts.current_season() and profile.best == 1024 and profile.card_matches == 1 and bob_cards.get("archer", {}).get("picks") == 2 and bob_cards.get("necromancer", {}).get("bans") == 1, "the profile carries the season and this season's card statistics")

	# Report the last opponent.
	alice.send_report("manner")
	check(await wait_for("alice", "report") == "", "a player reports the last opponent")
	alice.send_report("cheat")
	check(await wait_for("alice", "report") == "already_reported", "the same match is reported once")
	var line = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("reports.jsonl")).strip_edges())
	check(line is Dictionary and line.target_nickname == "용사" and line.reason == "manner", "the report names the opponent")

	# Cloud save.
	alice.send_cloud_load()
	check(await wait_for("alice", "cloud") == [0, ""], "no cloud save yet")
	alice.send_cloud_store(0, "{\"progress\":1}")
	check(await wait_for("alice", "stored") == [true, 1, ""], "the first cloud save is stored")
	server.cloud_store_times.clear()
	bob.send_cloud_load()
	check((await wait_for("bob", "cloud"))[0] == 0, "each account has its own save")
	alice.send_cloud_store(0, "{\"progress\":2}")
	check(await wait_for("alice", "stored") == [false, 1, "conflict"], "a store from a stale revision reports a conflict")
	alice.send_cloud_store(1, "{\"progress\":3}")
	check((await wait_for("alice", "stored"))[2] == "busy", "stores are rate limited")
	server.cloud_store_times.clear()
	alice.send_cloud_store(1, "{\"progress\":3}")
	check(await wait_for("alice", "stored") == [true, 2, ""], "a store on the current revision succeeds")
	carol.send_cloud_load()
	check(await wait_for("carol", "cloud") == [-1, ""], "guests have no cloud save")

	for client in [alice, bob, carol]: client.disconnect_from_server()
	await create_timer(0.2).timeout
	server.multiplayer.multiplayer_peer.close()
	preload("res://scripts/ServerBackup.gd")._remove_tree(directory)
	if failures == 0: print("PASS: %d ranked wire checks" % checks)
	quit(1 if failures else 0)
