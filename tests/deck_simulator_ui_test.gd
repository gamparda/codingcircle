extends SceneTree
## Deck editor → "덱 시뮬레이션" dialog → progress → verdict.

var failures := 0
var capture_dir := ""

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	call_deferred("run")

func run() -> void:
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main._build_deck_screen(0)
	await process_frame
	var button: Button = main.find_child("DeckSimulateButton", true, false)
	check(button != null, "deck editor offers the simulator")
	# An invalid selection (a card deselected) refuses to open the dialog.
	var first_unit: Button = main.find_child("DeckUnitGrid", true, false).get_child(0)
	var was_pressed := first_unit.button_pressed
	first_unit.button_pressed = not was_pressed
	button.pressed.emit()
	await process_frame
	check(main.find_child("DeckSimulatorPanel", true, false) == null, "invalid selection does not open the simulator")
	first_unit.button_pressed = was_pressed
	button.pressed.emit()
	await process_frame
	var panel = main.find_child("DeckSimulatorPanel", true, false)
	check(panel != null, "valid selection opens the simulator dialog")
	if panel == null:
		quit(1)
		return
	panel.stage_picker.select(0)
	panel.count_picker.select(0)
	panel.start()
	check(panel.start_button.disabled and panel.run != null, "starting locks the controls")
	var guard := 0
	while panel.run != null and guard < 4000:
		panel._process(0.016)
		guard += 1
	check(panel.run == null, "simulation finishes (%d slices)" % guard)
	check(panel.rate_label.text.ends_with("%") and not panel.start_button.disabled, "verdict appears and controls unlock")
	check(panel.chips.get_child_count() == 4, "result chips are shown")
	if capture_dir != "":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/deck-simulator.png" % capture_dir)
	main.find_child("CloseSimulatorButton", true, false).pressed.emit()
	await process_frame
	check(main.find_child("DeckSimulatorPanel", true, false) == null, "closing removes the dialog")
	print("deck_simulator_ui_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
