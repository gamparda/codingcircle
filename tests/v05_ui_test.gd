extends SceneTree

var main
var checks := 0
var failures := 0
var capture_dir := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func collect_text(node: Node) -> String:
	var text := ""
	if node is Label or node is Button: text = node.text + "\n"
	for child in node.get_children(): text += collect_text(child)
	return text

func _initialize() -> void:
	Engine.max_fps = 20
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	call_deferred("run")

func run() -> void:
	create_timer(45.0).timeout.connect(func(): printerr("v0.5 UI watchdog expired"); quit(1))
	var bootstrap := Control.new(); bootstrap.name="Bootstrap"
	get_root().add_child(bootstrap)
	bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main=load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	await process_frame
	main.set_process(false)
	main.save_data=load("res://scripts/SaveData.gd").default_data()
	main.save_data.tutorial_completed=true
	main.campaign_mode=false
	main._start_local_ai_battle(1)
	main.set_process(false)
	await process_frame
	main._on_snapshot(main.local_model.snapshot())
	check(main.red_hp_label.text=="320 / 320", "stage one displays its full 320 maximum")
	check(main.red_hp_bar.max_value==320.0 and main.red_hp_bar.value==320.0, "stage one health bar is completely full")
	check(main.blue_hp_label.text=="500 / 500", "player base remains unchanged")
	main.local_model.base_hp[1]=250.0
	main._on_snapshot(main.local_model.snapshot())
	check(main.red_hp_label.text=="250 / 320" and main.red_hp_bar.max_value==320.0, "damaged enemy retains the original stage maximum")
	var legacy: Dictionary=main.local_model.snapshot(); legacy.erase("base_max_hp")
	main._on_snapshot(legacy)
	check(main.red_hp_label.text=="250 / 500", "old-server snapshots retain a safe 500 fallback")
	main._start_local_ai_battle(8)
	main.set_process(false)
	await process_frame
	main._on_snapshot(main.local_model.snapshot())
	check(main.red_hp_label.text=="460 / 460", "final stage is also initially full")
	check(main.local_model.unit_decks[1]==ServerAI.stage_unit_deck(8), "real battle starts with the tactical stage deck")
	main._build_deck_screen(0)
	for frame in 3: await process_frame
	var copy := collect_text(main.root_background)
	check(copy.contains("유닛 3종 · 구조물 3종 선택"), "deck introduction is concise and actionable")
	check(not copy.contains("해골은 네크로맨서") and not copy.contains("서버가 이 덱을 검증"), "redundant deck explanations are removed")
	check(main.find_child("DeckCardsScroll",true,false)==null, "no-scroll deck layout remains")
	if not capture_dir.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(capture_dir)
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(capture_dir.path_join("concise-deck.png"))
		main._start_local_ai_battle(1); main.set_process(false)
		for frame in 3: await process_frame
		main._on_snapshot(main.local_model.snapshot())
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(capture_dir.path_join("full-stage-one-base.png"))
	bootstrap.queue_free()
	await process_frame
	if failures==0: print("PASS: %d v0.5 base HUD and concise-copy checks" % checks)
	quit(0 if failures==0 else 1)
