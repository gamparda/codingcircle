extends SceneTree

const Localization = preload("res://scripts/Localization.gd")
var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func press(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		if not button.disabled:
			button.pressed.emit()
		return
	var point := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		root.push_input(event)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			var folder := arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(folder)
			var path := folder.path_join(name + ".png")
			check(root.get_texture().get_image().save_png(path) == OK, "capture saved: " + path)

func tree_text(node: Node) -> String:
	var text := String(node.text) if node is Label or node is Button else ""
	for child in node.get_children():
		text += "\n" + tree_text(child)
	return text

func run() -> void:
	Engine.max_fps = 30
	Localization.install("ko")
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.save_data.last_deck = 0
	main.save_data.deck_presets[0].units = ["shield", "swordsman", "healer"]
	main.save_data.tutorial_completed = true
	var notes := main.find_child("PatchNotesButton", true, false) as Button
	check(notes != null, "menu exposes patch notes")
	press(notes)
	await process_frame
	await process_frame
	var scroll := main.find_child("PatchNotesScroll", true, false) as ScrollContainer
	var back := main.find_child("PatchNotesBack", true, false) as Button
	check(scroll != null and back != null, "patch notes open with scroll and fixed back action")
	check(tree_text(main).contains("v0.4.17") and tree_text(main).contains("v0.4.16"), "patch notes include current and previous releases")
	check(tree_text(main).contains("시전부터 7초") and tree_text(main).contains("8에서 2"), "patch notes describe shipped balance values")
	check(back.get_global_rect().end.y <= 720.0, "patch notes back action stays inside the viewport")
	capture("patch-notes")
	press(back)
	await process_frame
	check(main.find_child("PatchNotesButton", true, false) != null, "back returns to the main menu")
	main._start_local_ai_battle()
	main.set_process(false)
	await process_frame
	check(main.purchase_buttons.size() == 6, "all selected unit and structure cards track purchase costs")
	main.local_model.resources[0] = 0.0
	main._on_snapshot(main.local_model.snapshot())
	for button in main.purchase_buttons:
		check(button.disabled and is_equal_approx(button.modulate.r, 0.4), "unaffordable card and decoration are dark and disabled")
	var unit_button: Button = main.purchase_buttons[0]
	var before: int = main.local_model.units.size()
	press(unit_button)
	check(main.local_model.units.size() == before and main.local_model.resources[0] == 0.0, "disabled card cannot spend or spawn")
	main.local_model.resources[0] = 34.0
	main._on_snapshot(main.local_model.snapshot())
	for button in main.purchase_buttons:
		check(button.disabled == (float(button.get_meta("purchase_cost")) > 34.0), "affordability refresh respects each card's cost")
	await process_frame
	capture("purchase-state")
	main.local_model.resources[0] = float(unit_button.get_meta("purchase_cost"))
	main._on_snapshot(main.local_model.snapshot())
	check(not unit_button.disabled and unit_button.modulate == Color.WHITE, "card reactivates and brightens at the exact cost")
	press(unit_button)
	check(main.local_model.units.size() == before + 1, "reactivated card accepts a real purchase")
	main._on_snapshot(main.local_model.snapshot())
	check(unit_button.disabled, "spending dims the card again")
	main.queue_free()
	await process_frame
	print("PASS: %d focused purchase and patch-note checks" % checks) if failures == 0 else printerr("FAILED: %d of %d checks" % [failures, checks])
	quit(1 if failures else 0)
