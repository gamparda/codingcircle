extends SceneTree
## 계산 돕기: a game client lends CPU through its own connection, pauses during battles and leaves cleanly.

const HelperService = preload("res://scripts/assist/HelperService.gd")
var server
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

func make_server(port: int):
	var holder := Node.new(); holder.name = "HelperServer"; get_root().add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	return controller if controller.start_dedicated_server(port) else null

func wait_until(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	return predicate.call()

func finish() -> void:
	await create_timer(0.3).timeout
	if is_instance_valid(server): server.multiplayer.multiplayer_peer.close()
	print("helper_service_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func run() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("helper service watchdog"); finish())
	var port := 27993
	server = make_server(port)
	if server == null:
		await finish(); return
	server.configure_assist("")
	var service := HelperService.new()
	get_root().add_child(service)
	var in_battle := {"value": false}
	service.pause_check = func(): return in_battle.value
	check(not service.is_running(), "nothing runs before start")
	service.start({"candidates": ["127.0.0.1"], "port": port, "name": "시험 PC", "cores": 1, "capabilities": ["selftest"]})
	check(service.is_running(), "start brings the service up")
	check(await wait_until(func(): return service.worker.state == "idle"), "the PC joins through its own connection (%s)" % service.worker.state)
	check(server.assist.peers.size() == 1 and server.assist.peers.values()[0].role == "helper" and server.assist.peers.values()[0].name == "시험 PC", "the server sees a helper, not an assist server")
	check(service.network.client_session.is_empty() and service.network.client_assist_mode, "it never joins the lobby")

	var first: Dictionary = server.assist.queue.submit("selftest", {"chunks": 4}, "", "tester", float(Time.get_ticks_msec()) / 1000.0)
	check(await wait_until(func(): return server.assist.queue.jobs[int(first.id)].done), "the helper works through a job")
	check(server.assist.local_done_chunks == 0 and int(server.assist.result_for(int(first.id)).sum) == 20, "all of it by the helper, answer correct")

	# During a battle the helper rests.
	in_battle.value = true
	await create_timer(0.3).timeout
	var done_before: int = int(service.worker.stats.chunks)
	var second: Dictionary = server.assist.queue.submit("selftest", {"chunks": 3}, "", "tester", float(Time.get_ticks_msec()) / 1000.0)
	await create_timer(3.0).timeout
	check(service.worker.stats.chunks == done_before and server.assist.queue.summary(int(second.id)).done_chunks == 0, "no new work is taken while a battle runs")
	in_battle.value = false
	check(await wait_until(func(): return server.assist.queue.jobs[int(second.id)].done), "work resumes after the battle")

	# Switching it off says goodbye.
	service.stop()
	check(not service.is_running(), "stop takes the service down")
	check(await wait_until(func(): return server.assist.peers.is_empty()), "the server forgets the helper")
	await finish()
