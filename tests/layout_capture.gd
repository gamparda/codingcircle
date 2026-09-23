extends SceneTree

# Manual visual QA: run with xvfb-run at a 1280x720 virtual display.
func _init() -> void:
	call_deferred("capture")

func capture() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._build_settings_screen()
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_viewport().get_texture().get_image().save_png("/tmp/catwar-settings-layout.png")
	if result != OK:
		printerr("Settings screenshot failed: ", result)
		quit(1)
		return
	main._build_settings_screen(true)
	await process_frame
	await RenderingServer.frame_post_draw
	result = root.get_viewport().get_texture().get_image().save_png("/tmp/catwar-settings-mobile-layout.png")
	if result != OK:
		printerr("Mobile settings screenshot failed: ", result)
		quit(1)
		return
	main._build_connect_screen()
	await process_frame
	var code: LineEdit = main.find_child("RoomCodeInput", true, false)
	code.text = "abc233"
	code.set_caret_column(6)
	main._normalize_room_code_input(code.text)
	await RenderingServer.frame_post_draw
	result = root.get_viewport().get_texture().get_image().save_png("/tmp/catwar-room-layout.png")
	if result != OK:
		printerr("Room screenshot failed: ", result)
		quit(1)
		return
	main.save_data.tutorial_completed = true
	main._start_local_ai_battle(1)
	await process_frame
	await RenderingServer.frame_post_draw
	result = root.get_viewport().get_texture().get_image().save_png("/tmp/catwar-battle-layout.png")
	if result != OK:
		printerr("Battle screenshot failed: ", result)
		quit(1)
		return
	print("VISUAL_CAPTURES_OK")
	main.queue_free()
	await process_frame
	quit(0)
