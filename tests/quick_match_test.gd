extends SceneTree
const Queue = preload("res://scripts/QuickQueue.gd")
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

func require(predicate: Callable, message: String) -> bool:
	var okay: bool = await wait_until(predicate)
	check(okay, message)
	if not okay:
		await finish(1)
	return okay

func finish(code: int) -> void:
	if is_instance_valid(server): server.set_process(false)
	for controller in clients:
		if is_instance_valid(controller):
			controller.disconnect_from_server(); await create_timer(0.2).timeout
	await create_timer(0.15).timeout
	if is_instance_valid(server): server.multiplayer.multiplayer_peer.close()
	for path in server.replays.saved_paths if is_instance_valid(server) else []:
		DirAccess.remove_absolute(path)
	print("quick_match_test checks=%d failures=%d" % [checks, failures])
	quit(code)

func queue_rules() -> void:
	var queue := Queue.new()
	check(queue.enqueue(1, "가", 0) and not queue.enqueue(1, "가", 0), "a peer cannot queue twice")
	check(queue.take_pair(func(_id): return true).is_empty(), "one player alone is never paired")
	queue.enqueue(2, "나", 10); queue.enqueue(3, "다", 20)
	var pair := queue.take_pair(func(_id): return true)
	check(pair.size() == 2 and int(pair[0].peer) == 1 and int(pair[1].peer) == 2, "longest waiting players are paired first")
	check(queue.size() == 1 and queue.has(3), "unpaired player keeps waiting")
	queue.enqueue(4, "라", 30)
	check(queue.take_pair(func(id): return id != 3).is_empty() and queue.size() == 1 and queue.has(4), "ineligible (disconnected) players are dropped, not paired")
	check(queue.cancel(4) and not queue.cancel(4) and queue.size() == 0, "cancel removes exactly once")
	queue.enqueue(5, "마", 0); queue.enqueue(6, "바", Queue.MAX_WAIT_MSEC - 1)
	check(queue.expire(Queue.MAX_WAIT_MSEC) == [5] and queue.has(6), "only entries past the wait limit expire")
	for index in Queue.MAX_QUEUED + 10:
		queue.enqueue(1000 + index, "x", 0)
	check(queue.size() <= Queue.MAX_QUEUED, "queue size is bounded")

func run() -> void:
	create_timer(40.0).timeout.connect(func(): printerr("quick match watchdog"); finish(1))
	queue_rules()
	var port := 27986
	server = make_controller("QuickServer")
	if not server.start_dedicated_server(port):
		await finish(1); return
	var alpha = make_controller("알파"); var beta = make_controller("베타"); var gamma = make_controller("감마")
	clients = [alpha, beta, gamma]
	var statuses: Dictionary = {}
	for index in clients.size():
		clients[index].quick_match_status.connect(func(state): statuses[index] = state)
		clients[index].connect_to_server("127.0.0.1", port)
	if not await require(func(): return clients.all(func(c): return c.client_connection_state == "lobby"), "three clients reach the lobby"): return
	check(not gamma.cancel_quick_match(), "cancel without queuing is a no-op")
	check(alpha.start_quick_match(), "alpha starts a quick match")
	if not await require(func(): return statuses.get(0, "") == "queued" and alpha.client_connection_state == "queued", "server confirms alpha is queued"): return
	check(not alpha.start_quick_match(), "a queued client cannot queue again")
	check(not alpha.join_session_room("ABC234"), "a queued client cannot join other rooms")
	check(server.quick_queue.size() == 1 and not alpha.client_in_match, "one queued player does not start a battle")
	check(alpha.cancel_quick_match(), "alpha cancels")
	if not await require(func(): return statuses.get(0, "") == "cancelled" and alpha.client_connection_state == "lobby" and server.quick_queue.size() == 0, "cancel returns alpha to the lobby and empties the queue"): return
	alpha.start_quick_match()
	beta.start_quick_match()
	if not await require(func(): return alpha.client_in_match and beta.client_in_match, "two queued players are paired into a running battle"): return
	check(alpha.client_session.get("phase", "") == "playing" and alpha.client_session.name == "빠른 대전" and alpha.client_session.members.size() == 2, "pairing creates a normal session room with both players")
	check(alpha.client_session.members.all(func(m): return m.role == "player"), "both are players")
	check(server.quick_queue.size() == 0 and not gamma.client_in_match, "third client is untouched")
	gamma.start_quick_match()
	if not await require(func(): return gamma.client_connection_state == "queued", "gamma waits alone"): return
	gamma.disconnect_from_server()
	if not await require(func(): return server.quick_queue.size() == 0, "disconnecting while queued leaves the queue"): return
	alpha.send_spawn("swordsman")
	if not await require(func(): return server.models.size() == 1 and server.models.values()[0].units.size() == 1, "server simulates the quick match"): return
	check(alpha.send_surrender(), "alpha surrenders")
	if not await require(func(): return server.replays.saved_paths.size() == 1, "server saved a replay of the finished quick match"): return
	var BattleReplay = load("res://scripts/BattleReplay.gd")
	var replay: Dictionary = BattleReplay.load_file(server.replays.saved_paths[0])
	check(not replay.is_empty() and replay.meta.mode == "quick" and bool(BattleReplay.verify(replay).ok), "the saved quick-match replay verifies")
	await finish(0 if failures == 0 else 1)
