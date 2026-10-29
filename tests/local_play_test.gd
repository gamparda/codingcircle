extends SceneTree
# Same Wi-Fi play: the app hosts with its own server code, a second device joins by address or beacon, both
# get a friendly match, and nothing ranked or account-bound reaches the local host.
const LocalPlay = preload("res://scripts/net/LocalPlay.gd")
const LocalPlayScreen = preload("res://scripts/screens/LocalPlayScreen.gd")
const ServerLink = preload("res://scripts/ServerLink.gd")

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	Engine.max_fps = 30
	call_deferred("run")

func wait_until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	return predicate.call()

func make_guest():
	var holder := Node.new(); holder.name = "Guest"; root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	controller.set_room_request("session"); controller.client_nickname = "친구"
	controller.set_client_deck(BattleModel.DEFAULT_UNIT_DECK, BattleModel.DEFAULT_STRUCTURE_DECK)
	return controller

func run() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("local play watchdog"); quit(1))
	# Pure helpers.
	check(LocalPlay.broadcast_addresses(["127.0.0.1", "192.168.43.1", "10.0.0.7", "fe80::1", "169.254.3.4"]) == ["255.255.255.255", "192.168.43.255", "10.0.0.255"], "beacons go to the general and each local /24 broadcast")
	var packet := LocalPlay.beacon_packet("방장이름이아주아주아주아주길어요", LocalPlay.HOST_PORT)
	var info := LocalPlay.parse_beacon(packet)
	check(info.name.length() <= 16 and info.port == LocalPlay.HOST_PORT and info.version == preload("res://scripts/ServerStats.gd").ruleset_id(), "a beacon carries the host name, port and game version")
	check(LocalPlay.parse_beacon("{\"magic\":\"other\",\"name\":\"x\",\"version\":\"1\",\"port\":1}").is_empty() and LocalPlay.parse_beacon("not json").is_empty() and LocalPlay.parse_beacon(packet.replace(str(LocalPlay.HOST_PORT), "99999")).is_empty(), "foreign or broken beacons are ignored")
	check(LocalPlay.valid_address("192.168.43.1") and not LocalPlay.valid_address("192.168.43") and not LocalPlay.valid_address("300.1.1.1") and not LocalPlay.valid_address("a.b.c.d"), "typed addresses are checked")
	check(LocalPlay.shareable_addresses(["127.0.0.1", "10.0.0.7", "192.168.43.1"]) == ["192.168.43.1", "10.0.0.7"], "the hotspot address is shown first")

	var bootstrap := Control.new(); bootstrap.name = "Bootstrap"; root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate(); bootstrap.add_child(main)
	main.updater.enabled = false
	main.save_data = SaveData.default_data(); main.save_data.tutorial_completed = true
	await process_frame

	# Discovery: a beacon sent straight to the listener shows up in the dialog's list.
	main._build_lobby_screen()
	LocalPlayScreen.show(main)
	check(main.root_background.find_child("LocalHostButton", true, false) != null and main.root_background.find_child("LocalAddressInput", true, false) != null, "the dialog offers hosting and joining by address")
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", LocalPlay.DISCOVERY_PORT)
	sender.put_packet(LocalPlay.beacon_packet("방장", LocalPlay.HOST_PORT).to_utf8_buffer())
	check(await wait_until(func(): return main.local_play.host_list().size() == 1), "a host on the network is found")
	check(await wait_until(func(): return main.root_background.find_child("LocalJoin_127_0_0_1", true, false) != null), "the found host can be joined from the list")
	sender.put_packet(JSON.stringify({"magic": LocalPlay.MAGIC, "name": "옛버전", "version": "0.0.1", "port": LocalPlay.HOST_PORT}).to_utf8_buffer())
	await wait_until(func(): return main.local_play.host_list().size() == 1 and not main.local_play.host_list()[0].compatible)
	check(main.local_play.host_list()[0].compatible == false, "a host on another game version is marked and cannot be joined")
	sender.close()

	# Hosting: the app's own server, and its own client in the host's lobby.
	LocalPlayScreen.host(main)
	check(main.local_play.hosting() and main.local_target == "127.0.0.1" and main.local_play.listener == null, "hosting starts the in-app server and stops searching")
	check(await wait_until(func(): return main.network.client_connection_state == "lobby"), "the host plays through its own server")
	check(not main.network.client_transport_verified and not main.network.account_ready(), "no account credentials go to a local host")
	var subtitle: Label = main.root_background.find_child("LobbySubtitle", true, false)
	check(subtitle != null and subtitle.text.contains("내가 방장"), "the lobby says this device is the host")
	check(main.ranked_button_ref.disabled, "ranked play is off on a local host")
	var link_message := []
	ServerLink.run(main, func(): link_message.append("ran"), func(text): link_message.append(text))
	check(link_message.size() == 1 and String(link_message[0]).contains("같은 와이파이"), "server-only features stay off during local play")

	# A friend joins by address and both start a quick match.
	var guest = make_guest()
	guest.connect_to_candidates(["127.0.0.1"], LocalPlay.HOST_PORT)
	check(await wait_until(func(): return guest.client_connection_state == "lobby"), "a second device joins the host by address")
	var found := []
	main.network.match_found.connect(func(side): found.append(["host", side]))
	guest.match_found.connect(func(side): found.append(["guest", side]))
	main._toggle_quick_match()
	guest.start_quick_match()
	check(await wait_until(func(): return found.size() == 2), "both players are matched on the local host")
	check(main.local_play.host_server.models.size() == 1, "the host computes the battle")
	guest.start_ranked_match()
	await create_timer(0.3).timeout
	check(main.local_play.host_server.ranked_queue.entries.is_empty(), "nobody can queue for ranked on a local host")

	# Leaving stops the host and returns to the official server.
	guest.disconnect_from_server()
	main.network.disconnect_from_server()
	preload("res://scripts/screens/LobbyFlow.gd").leave_local(main)
	check(not main.local_play.hosting() and main.local_target.is_empty(), "leaving stops hosting")
	await create_timer(0.3).timeout
	var again = LocalPlay.new()
	root.add_child(again)
	check(again.start_host("다시", LocalPlay.HOST_PORT), "the port is free again after leaving")
	again.stop_all()
	await create_timer(0.2).timeout
	if failures == 0: print("PASS: %d local play checks" % checks)
	quit(1 if failures else 0)
