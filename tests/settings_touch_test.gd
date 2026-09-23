extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._build_settings_screen(true)
	await process_frame
	var scroll := main.find_child("SettingsScroll", true, false) as ScrollContainer
	var option := scroll.get_child(0).get_child(2) as CheckButton
	var initial_state := option.button_pressed
	var start := option.get_global_rect().get_center()
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.position = start
	touch.pressed = true
	root.push_input(touch)
	for step in 25:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = start + Vector2(0, -10 * (step + 1))
		drag.relative = Vector2(0, -10)
		root.push_input(drag)
	touch.position = start + Vector2(0, -250)
	touch.pressed = false
	root.push_input(touch)
	await process_frame
	var quality := main.find_child("GraphicsQualitySelector", true, false) as OptionButton
	var resolution = main.find_child("ResolutionSelector", true, false)
	var fps = main.find_child("FPSSelector", true, false)
	var nested_popup := false
	for child in scroll.get_child(0).get_children():
		if child is OptionButton:
			nested_popup = true
	if scroll.scroll_vertical <= 0 or option.button_pressed != initial_state or nested_popup or quality == null or quality.get_parent() == scroll.get_child(0) or resolution != null or fps != null:
		printerr("FAIL: Android swipe must scroll without toggling controls or exposing popups")
		quit(1)
		return
	quality.select(3)
	quality.item_selected.emit(3)
	var save_button := main.find_child("SettingsSaveButton", true, false) as Button
	if save_button == null:
		printerr("FAIL: save button is missing")
		quit(1)
		return
	save_button.pressed.emit()
	await process_frame
	if main.save_data.settings.graphics_quality != "low" or main.save_data.settings.fps_limit != 30 or main.save_data.settings.window_size != "1280x720" or main.save_data.settings.battle_effects:
		printerr("FAIL: low preset did not persist its FPS, resolution and effects: ", main.save_data.settings)
		quit(1)
		return
	print("PASS: Android settings swipe scrolls without triggering options")
	print("PASS: low graphics preset saves a 30 FPS reduced-effects profile")
	main.queue_free()
	await process_frame
	quit(0)
