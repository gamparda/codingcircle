extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	await process_frame
	Engine.max_fps = 30
	var result: Dictionary = {"code": ""}
	main.network.room_created.connect(func(code): result.code = code)
	main._connect_for_room("create")
	var started := Time.get_ticks_msec()
	while String(result.code).is_empty() and Time.get_ticks_msec() - started < 12000:
		await process_frame
	var successful: bool = NetworkController.is_valid_room_code(String(result.code)) and main.room_code_input.text == String(result.code) and main.network.client_connection_state == "waiting"
	if successful:
		print("PASS: create-room UI receives and prominently displays a real server-generated code")
	else:
		printerr("FAIL: room creation state=", main.network.client_connection_state, " status=", main.status_label.text)
	main.network.disconnect_from_server()
	main.queue_free()
	await process_frame
	quit(0 if successful else 1)
