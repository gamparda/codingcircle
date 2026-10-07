extends SceneTree
## Visual QA: renders the main screens to PNGs. Needs a real renderer (not --headless).
##   godot --path . --script res://tools/capture_screens.gd -- --out=C:/some/dir

var out_dir := "user://captures"

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("run")

func shot(name: String, frames: int = 3) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])

func run() -> void:
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	main.save_data.tutorial_completed = true
	await shot("01_menu")
	main._build_ai_stage_screen(true)
	await shot("02_campaign")
	main._build_deck_screen()
	await shot("03_deck")
	main._build_settings_screen()
	await shot("04_settings")
	main._build_records_screen()
	await shot("05_records")
	main._build_patch_notes_screen()
	await shot("06_patchnotes")
	main._build_lobby_screen()
	main.network.client_connection_state = "lobby"
	main._on_room_list({"rooms":[{"code":"ABC233","name":"같이 대전해요","players":1,"state":"waiting"},{"code":"DEF456","name":"고수만 오세요","players":2,"state":"playing","locked":true,"spectators":3}],"page":0,"total":2})
	await shot("07_lobby")
	main.campaign_mode = true
	main._show_stage_brief(3)
	await shot("07b_brief", 4)
	main._dismiss_action_overlay()
	main._start_local_ai_battle(3)
	for i in 240:
		await process_frame
	main._purchase_unit(main.battle_preset.units[0])
	for i in 120:
		await process_frame
	await shot("08_battle")
	main._show_stats_panel()
	await shot("08b_stats", 4)
	main._dismiss_stats_panel()
	main.local_model.winner = 0
	main._on_snapshot(main.local_model.snapshot())
	await shot("09_result", 8)
	print("CAPTURES_DONE ", out_dir)
	quit(0)
