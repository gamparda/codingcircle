extends SceneTree

var checks := 0
var failures := 0
var main
var capture_dir := ""
var main_script := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func click(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
		return
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_root().push_input(event, true)
		await process_frame

func _initialize() -> void:
	Engine.max_fps = 30
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--main-script="): main_script = arg.trim_prefix("--main-script=")
	call_deferred("run")

func run() -> void:
	create_timer(45.0).timeout.connect(func(): printerr("Deck layout watchdog expired"); quit(1))
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	get_root().add_child(bootstrap)
	bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main = load("res://scenes/Main.tscn").instantiate()
	if not main_script.is_empty(): main.set_script(load(main_script))
	bootstrap.add_child(main)
	await process_frame
	main.set_process(false)
	main.save_data = load("res://scripts/SaveData.gd").default_data()
	main.save_data.tutorial_completed = true
	main.save_data.deck_presets[0].units = ["berserker", "warlock", "necromancer"]
	main._build_deck_screen(0)
	for frame in 4: await process_frame
	var panel = main.find_child("DeckPanel", true, false)
	var units = main.find_child("DeckUnitGrid", true, false)
	var structures = main.find_child("DeckStructureGrid", true, false)
	var save = main.find_child("DeckSaveButton", true, false)
	check(main.find_child("DeckCardsScroll", true, false) == null, "deck has no scroll container")
	check(panel != null and panel.position.y >= 0 and panel.position.y + panel.size.y <= 720.0, "taller deck panel fits the logical 720p canvas")
	check(units != null and units.get_child_count() == 7, "all seven purchasable units remain")
	check(structures != null and structures.columns == 4 and structures.get_child_count() == 4, "all four structures fill a four-column row")
	if panel == null or units == null or structures == null or save == null: quit(1); return
	for index in 4:
		var unit: Button = units.get_child(index)
		var structure: Button = structures.get_child(index)
		check(absf(unit.get_global_rect().position.x - structure.get_global_rect().position.x) <= 1.0, "unit and structure column alignment %d" % index)
		check(absf(unit.size.x - structure.size.x) <= 1.0, "equal card widths %d" % index)
		check(absf(unit.size.y - structure.size.y) <= 1.0, "equal card heights %d" % index)
		check(structure.size.y >= structure.get_combined_minimum_size().y, "structure text is not clipped %d" % index)
	check(absf(structures.get_child(3).position.x + structures.get_child(3).size.x - structures.size.x) <= 1.0, "generator reaches the right edge without an empty fifth slot")
	check(units.position.y + units.size.y < structures.position.y, "the structure row does not overlap unit cards")
	check(structures.get_global_rect().end.y < save.get_global_rect().position.y, "structure cards and action row do not overlap")
	var card = main.find_child("DeckStructure_swamp", true, false)
	var before: bool = card.button_pressed
	await click(card)
	check(card.button_pressed != before, "actual structure-card click still toggles selection")
	await click(save)
	for frame in 3: await process_frame
	var errors := []
	for node in main.find_children("*", "Label", true, false):
		if node.text == "유닛과 구조물을 각각 정확히 3종 선택해야 합니다.": errors.append(node)
	check(errors.size() == 1, "invalid deck shows the existing selection-count message")
	check(panel.position.y + panel.size.y <= 720.0 and structures.get_global_rect().end.y < save.get_global_rect().position.y, "validation message does not push cards outside the panel")
	await click(card)
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(capture_dir)
		main._build_deck_screen(0)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(capture_dir.path_join("deck-no-scroll.png"))
	bootstrap.queue_free()
	await process_frame
	if failures == 0: print("PASS: %d focused deck layout and pointer checks" % checks)
	quit(0 if failures == 0 else 1)
