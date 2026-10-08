extends SceneTree
## A real assist client against a real server: joining, working, handing in, wrapping up and being turned away.

const AssistWorker = preload("res://scripts/assist/AssistWorker.gd")
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
	Engine.max_fps = 30
	call_deferred("run")

func make_controller(label: String):
	var holder := Node.new(); holder.name = label; get_root().add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	controller.client_nickname = label
	clients.append(controller)
	return controller

func make_worker(label: String, port: int, cores: int):
	var controller = make_controller(label)
	var worker := AssistWorker.new()
	get_root().add_child(worker)
	worker.setup(controller)
	worker.config.candidates = ["127.0.0.1"]
	worker.config.port = port
	worker.config.name = label
	worker.config.cores = cores
	worker.config.capabilities = ["selftest"]
	return worker

func wait_until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	return predicate.call()

func finish(code: int) -> void:
	for controller in clients:
		if is_instance_valid(controller):
			controller.disconnect_from_server()
	await create_timer(0.3).timeout
	if is_instance_valid(server): server.multiplayer.multiplayer_peer.close()
	print("assist_wire_test checks=%d failures=%d" % [checks, failures])
	quit(code)

func run() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("assist wire watchdog"); finish(1))
	var port := 27991
	server = make_controller("AssistMain")
	if not server.start_dedicated_server(port):
		await finish(1); return
	server.configure_assist("")


	# A proper helper joins, orders a job and does it itself.
	var worker = make_worker("보조1", port, 2)
	var results := []
	worker.job_result.connect(func(id, result): results.append([id, result]))
	worker.start()
	check(await wait_until(func(): return worker.state == "idle"), "the helper joins (%s)" % worker.state)
	check(server.assist.peers.size() == 1 and server.assist.peers.values()[0].name == "보조1" and server.assist.peers.values()[0].cores == 2, "the server knows its name and cores")
	worker.submit_job("selftest", {"chunks": 6}, "점검 작업")
	check(await wait_until(func(): return not results.is_empty()), "the submitter receives the finished job (%s)" % [results])
	check(not results.is_empty() and int(results[0][1].sum) == 42 and int(results[0][1].chunks) == 6, "the combined answer is right")
	check(server.assist.local_done_chunks == 0 and worker.stats.chunks == 6, "the helper did all six chunks, the main server none")
	check(await wait_until(func(): return not worker.overview.is_empty() and int(worker.overview.totals.jobs_done) == 1), "the overview shows the finished job")
	check(worker.journal.lines.any(func(entry): return String(entry.text).contains("완료")) and worker.journal.lines.any(func(entry): return String(entry.text).contains("연결되었습니다")), "the log tells what happened")

	# Wrapping up half way: finished chunks stay, the rest goes to the main server, nothing is lost or repeated.
	results.clear()
	worker.config.cores = 1
	worker.submit_job("selftest", {"chunks": 50}, "큰 점검")
	check(await wait_until(func(): return worker.stats.chunks >= 9), "the helper starts on the big job")
	var before: int = int(worker.stats.chunks)
	worker.begin_wrap_up("시험")
	check(worker.state == "wrapping", "wrapping up begins")
	check(await wait_until(func(): return worker.state == "stopped"), "the helper finishes its chunk and stops (%s)" % worker.state)
	check(server.assist.peers.is_empty(), "the server forgot the helper")
	check(await wait_until(func(): return server.assist.queue.jobs.has(2) and server.assist.queue.jobs[2].done, 20.0), "the main server finishes the rest on its own")
	var answer: Dictionary = server.assist.result_for(2)
	check(int(answer.sum) == 2550 and int(answer.chunks) == 50, "every chunk was done exactly once: sum %s" % [answer.get("sum")])
	check(server.assist.local_done_chunks > 0 and server.assist.local_done_chunks + int(worker.stats.chunks) - 6 == 50, "split between the helper (%d) and the main server (%d)" % [int(worker.stats.chunks) - 6, server.assist.local_done_chunks])
	check(int(worker.stats.chunks) - 6 >= before - 6, "chunks the helper reported before leaving were kept")
	await finish(0 if failures == 0 else 1)
