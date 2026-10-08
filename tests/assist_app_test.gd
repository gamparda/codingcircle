extends SceneTree
## The assist server window: its widgets, saved settings, the connect flow against a real server, the log and results.

const AssistApp = preload("res://scripts/assist/AssistApp.gd")
var server
var clients: Array = []
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	Engine.max_fps = 30
	call_deferred("run")

func make_controller(label: String):
	var holder := Node.new(); holder.name = label; get_root().add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	clients.append(controller)
	return controller

func wait_until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	return predicate.call()

func finish() -> void:
	for controller in clients:
		if is_instance_valid(controller):
			controller.disconnect_from_server()
	await create_timer(0.3).timeout
	if is_instance_valid(server): server.multiplayer.multiplayer_peer.close()
	DirAccess.remove_absolute("user://assist_app_test.json")
	print("assist_app_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)

func run() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("assist app watchdog"); finish())
	DirAccess.remove_absolute("user://assist_app_test.json")
	var port := 27992
	server = make_controller("AssistAppMain")
	if not server.start_dedicated_server(port):
		await finish(); return
	server.configure_assist("")
	var client = make_controller("보조창")
	var app = AssistApp.new()
	app.config_path = "user://assist_app_test.json"
	get_root().add_child(app)
	app.setup(client)
	await process_frame

	# The window is complete.
	for node_name in ["AssistAddress", "AssistName", "AssistConnectButton", "AssistStatus", "CoreSlider", "AutoConnect", "RunningRows", "QueueRows", "ResultRows", "AssistLog", "LogFilter", "PauseButton", "WrapUpButton", "StopNowButton", "NewJobType", "NewJobButton", "Cap_balance", "Cap_replay", "Cap_selftest"]:
		check(app.find_child(node_name, true, false) != null, "the window has %s" % node_name)
	check(app.find_child("Cap_stats", true, false).disabled and app.find_child("Cap_backup", true, false).disabled and app.find_child("Cap_archive", true, false).disabled, "work that is not available yet is listed but cannot be ticked")
	check(app.address_input.text == AssistApp.DEFAULT_ADDRESS, "a fresh install already points at the main server")
	check(app.wrap_button.disabled and app.stop_button.disabled and app.job_button.disabled, "nothing to stop or order while offline")
	check(app.status_label.text.contains("연결 안 됨"), "the status says offline")

	# Connecting without an address or without any work selected explains itself.
	app.address_input.text = ""
	app.find_child("AssistConnectButton", true, false).pressed.emit()
	check(app.worker.journal.lines.any(func(entry): return entry.level == "warn" and String(entry.text).contains("주소")), "a missing address is explained in the log")
	app.address_input.text = "127.0.0.1:%d" % port
	for id in app.cap_boxes:
		app.cap_boxes[id].button_pressed = false
	app.find_child("AssistConnectButton", true, false).pressed.emit()
	check(app.worker.journal.lines.any(func(entry): return String(entry.text).contains("작업을 하나 이상")), "choosing no work at all is explained too")

	# Settings are read, used and saved.
	app.cap_boxes["selftest"].button_pressed = true
	app.core_slider.value = 1
	app.address_input.text = "127.0.0.1:%d" % port
	app.name_input.text = "시험 보조"
	app._read_widgets()
	app._save_config()
	check(app.worker.config.capabilities == ["selftest"] and app.worker.config.cores == 1 and app.worker.config.port == port and app.worker.config.candidates == ["127.0.0.1"] and app.worker.config.name == "시험 보조", "the widgets feed the worker's settings")
	var saved = JSON.parse_string(FileAccess.get_file_as_string("user://assist_app_test.json"))
	check(saved is Dictionary and not saved.has("token") and saved.cores == 1 and saved.capabilities == ["selftest"], "the settings are saved to disk")

	# The real connection.
	app.find_child("AssistConnectButton", true, false).pressed.emit()
	check(await wait_until(func(): return app.worker.state == "idle"), "the window connects (%s)" % app.worker.state)
	app._refresh()
	check(app.status_label.text.contains("대기 중") and app.connect_button.text == "연결 해제" and not app.wrap_button.disabled and not app.job_button.disabled, "the status and buttons reflect the connection")
	check(server.assist.peers.size() == 1 and server.assist.peers.values()[0].name == "시험 보조", "the server sees the window's name")
	app.job_type.select(1)
	app.find_child("NewJobButton", true, false).pressed.emit()
	check(await wait_until(func(): return app.result_rows.get_child_count() >= 2 and app.worker.stats.chunks >= 8), "an ordered job is done and its result shown")
	check(app.worker.journal.lines.any(func(entry): return String(entry.text).contains("완료 · 결과를 받았습니다")), "the log reports the finished job")
	check(await wait_until(func(): return not app.worker.overview.is_empty() and int(app.worker.overview.totals.jobs_done) >= 1), "the main server's queue arrives")
	app._refresh()
	check(app.queue_rows.get_child_count() >= 1 and app.queue_summary.text.contains("완료"), "the queue list shows the finished job")
	check(app.uptime_label.text.contains("처리한 조각 8개"), "the header counts processed chunks")

	# The log: levels, filter and the text on screen.
	app.worker.journal.add("warn", "경고 시험")
	app.worker.journal.add("error", "오류 [시험]")
	check(app.log_view.get_parsed_text().contains("경고 시험") and app.log_view.get_parsed_text().contains("오류 [시험]"), "log lines appear (brackets included)")
	app.log_filter.select(2)
	app._rebuild_log()
	check(app.log_view.get_parsed_text().contains("오류 [시험]") and not app.log_view.get_parsed_text().contains("경고 시험"), "the filter keeps only errors")
	app.log_filter.select(0)
	app._rebuild_log()
	check(app.worker.journal.as_text("warn").contains("경고 시험") and not app.worker.journal.as_text("error").contains("경고 시험"), "copying respects the level")

	# Pausing, and the wrap-up button.
	app.find_child("PauseButton", true, false).pressed.emit()
	check(app.worker.paused and app.pause_button.text == "재개", "pause stops taking work")
	app.find_child("PauseButton", true, false).pressed.emit()
	check(not app.worker.paused, "and resume restarts it")
	app.find_child("WrapUpButton", true, false).pressed.emit()
	check(await wait_until(func(): return app.worker.state == "stopped"), "the wrap-up button ends the session")
	app._refresh()
	check(app.status_label.text.contains("종료됨") and app.wrap_button.disabled and server.assist.peers.is_empty(), "the window shows it stopped and the server forgot it")
	await finish()
