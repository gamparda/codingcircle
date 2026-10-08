extends SceneTree
## The public room list shows running battles (names, decks, elapsed time) and can be filtered by the server.

var server
var clients: Array = []
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
	if is_instance_valid(server): server.set_process(false)
	for controller in clients:
		if is_instance_valid(controller):
			controller.disconnect_from_server(); await create_timer(0.2).timeout
	await create_timer(0.15).timeout
	if is_instance_valid(server): server.multiplayer.multiplayer_peer.close()
	for path in server.replays.saved_paths if is_instance_valid(server) else []:
		DirAccess.remove_absolute(path)
	print("live_room_list_test checks=%d failures=%d" % [checks, failures])
	quit(code)

func validation_rules() -> void:
	var live := {"names": ["가", "나"], "elapsed": 12.5, "units": [["shield", "archer", "healer"], ["berserker", "warlock", "necromancer"]]}
	var room := {"code": "ABC234", "name": "빠른 대전", "players": 2, "locked": false, "state": "playing", "spectators": 0, "live": live}
	check(NetworkController.is_valid_room_listing({"rooms": [room], "page": 0, "total": 1}), "a running battle may carry live details")
	var waiting := room.duplicate(true)
	waiting.state = "waiting"
	check(not NetworkController.is_valid_room_listing({"rooms": [waiting], "page": 0, "total": 1}), "live details only belong to running battles")
	for broken in [{"names": ["가"], "elapsed": 1.0, "units": live.units}, {"names": ["가", "나"], "elapsed": -1.0, "units": live.units}, {"names": ["가", "나"], "elapsed": 1.0, "units": [["x", "y", "z"], live.units[1]]}, {"names": ["가", "나"], "elapsed": 1.0, "units": live.units, "extra": 1}, {"names": [5, "나"], "elapsed": 1.0, "units": live.units}]:
		var copy := room.duplicate(true)
		copy.live = broken
		check(not NetworkController.is_valid_room_listing({"rooms": [copy], "page": 0, "total": 1}), "rejects a bad live block %s" % [broken])
	var rooms := [{"code": "AAAAAA", "state": "waiting", "spectators": 0}, {"code": "BBBBBB", "state": "playing", "spectators": 1}, {"code": "CCCCCC", "state": "playing", "spectators": 4}, {"code": "DDDDDD", "players": 1}]
	check(NetworkController.filtered_listing(rooms, "all").size() == 4, "the default filter keeps everything")
	check(NetworkController.filtered_listing(rooms, "waiting").map(func(r): return r.code) == ["AAAAAA", "DDDDDD"], "waiting keeps rooms that can still be joined")
	check(NetworkController.filtered_listing(rooms, "live").map(func(r): return r.code) == ["CCCCCC", "BBBBBB"], "live keeps running battles, most watched first")

func run() -> void:
	create_timer(40.0).timeout.connect(func(): printerr("live room list watchdog"); finish(1))
	validation_rules()
	var port := 27988
	server = make_controller("LiveServer")
	if not server.start_dedicated_server(port):
		await finish(1); return
	var alpha = make_controller("알파"); var beta = make_controller("베타"); var watcher = make_controller("구경꾼")
	clients = [alpha, beta, watcher]
	var lists := []
	watcher.room_list_received.connect(func(data): lists.append(data))
	for client in clients:
		client.connect_to_server("127.0.0.1", port)
	if not await wait_until(func(): return clients.all(func(c): return c.client_connection_state == "lobby")):
		check(false, "three clients reach the lobby"); await finish(1); return
	alpha.start_quick_match()
	beta.start_quick_match()
	if not await wait_until(func(): return alpha.client_in_match and beta.client_in_match):
		check(false, "the pair starts a battle"); await finish(1); return
	watcher.browse_rooms(0)
	check(await wait_until(func(): return not lists.is_empty() and lists.back().rooms.any(func(r): return r.has("live"))), "the lobby list carries live details for the running battle")
	var room: Dictionary = lists.back().rooms.filter(func(r): return r.has("live"))[0]
	check(room.live.names.has("알파") and room.live.names.has("베타") and room.live.units.size() == 2 and room.state == "playing", "names and decks are public")
	var seen := lists.size()
	watcher.set_room_filter("waiting")
	check(await wait_until(func(): return lists.size() > seen) and lists.back().rooms.all(func(r): return String(r.get("state", "waiting")) == "waiting"), "the waiting filter hides running battles")
	seen = lists.size()
	watcher.set_room_filter("live")
	check(await wait_until(func(): return lists.size() > seen) and lists.back().total == 1 and lists.back().rooms[0].has("live"), "the live filter shows only the running battle")
	seen = lists.size()
	watcher.set_room_filter("nonsense")
	await create_timer(0.4).timeout
	check(lists.size() == seen, "unknown filters are ignored")
	seen = lists.size()
	watcher.browse_rooms(0)
	check(await wait_until(func(): return lists.size() > seen) and lists.back().total == 1, "paging keeps the chosen filter")
	await finish(0 if failures == 0 else 1)
