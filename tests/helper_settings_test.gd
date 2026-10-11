extends SceneTree
## Helper settings and save failures in settings/deck screens.

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var save := SaveData.default_data()
	check(not save.settings.helper_enabled and not save.settings.has("helper_token") and save.settings.helper_cores == 1, "helping is off by default")
	var stored := SaveData.sanitize(JSON.parse_string(JSON.stringify({"settings": {"helper_enabled": true, "helper_cores": 5, "language": "ko"}})))
	check(stored.settings.helper_enabled and stored.settings.helper_cores == 5, "the values survive saving")
	var junk := SaveData.sanitize({"settings": {"helper_enabled": "yes", "helper_cores": 9999}})
	check(not junk.settings.helper_enabled and junk.settings.helper_cores == 64, "junk is dropped or clamped")
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	main.link_enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	var original: Dictionary = main.save_data.duplicate(true)
	check(SaveData.save_data(original), "baseline profile can be saved")
	var original_text := FileAccess.get_file_as_string(SaveData.SAVE_PATH)
	main._build_settings_screen()
	await process_frame
	for node_name in ["HelperToggle", "HelperCores", "HelperCoresLabel"]:
		check(main.find_child(node_name, true, false) != null, "settings has %s" % node_name)
	main.find_child("HelperToggle", true, false).button_pressed = true
	main.find_child("HelperCores", true, false).value = 1
	check(DirAccess.make_dir_absolute(SaveData.SAVE_PATH + ".tmp") == OK, "blocked settings staging path created")
	main.find_child("SettingsSaveButton", true, false).pressed.emit()
	await process_frame
	check(main.save_data == original and FileAccess.get_file_as_string(SaveData.SAVE_PATH) == original_text, "failed settings save keeps the active profile and disk file")
	check(main.find_child("SettingsDirty", true, false).text.contains("저장하지 못했습니다") and main.find_child("HelperToggle", true, false).button_pressed, "failure stays on screen, explains the error and keeps input for retry")
	DirAccess.remove_absolute(SaveData.SAVE_PATH + ".tmp")
	main.find_child("SettingsSaveButton", true, false).pressed.emit()
	await process_frame
	check(main.save_data.settings.helper_enabled and main.save_data.settings.helper_cores == 1, "saving the settings stores them")
	check(main.helper_service == null, "headless runs never start the service")
	# Cancelling discards previews and does not persist edited values.
	main._build_settings_screen()
	await process_frame
	var slider: HSlider = main.find_child("MasterVolumeSlider", true, false)
	slider.value = 0.2
	main.find_child("SettingsCancelButton", true, false).pressed.emit()
	await process_frame
	check(main.save_data.settings.master_volume == original.settings.master_volume, "cancel does not commit volume preview")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), linear_to_db(float(original.settings.master_volume))), "cancel restores the previous audio volume")
	# The same transaction rule applies to the deck and its starter goal.
	original = main.save_data.duplicate(true)
	original_text = FileAccess.get_file_as_string(SaveData.SAVE_PATH)
	main._build_deck_screen(1)
	await process_frame
	main.find_child("NameEdit", true, false).text = "재시도 덱"
	check(DirAccess.make_dir_absolute(SaveData.SAVE_PATH + ".tmp") == OK, "blocked deck staging path created")
	main.find_child("DeckSaveButton", true, false).pressed.emit()
	await process_frame
	check(main.save_data == original and FileAccess.get_file_as_string(SaveData.SAVE_PATH) == original_text, "failed deck save does not switch presets or complete the goal")
	check(main.find_child("Status", true, false).text.contains("저장하지 못했습니다") and main.find_child("NameEdit", true, false).text == "재시도 덱", "deck save failure preserves edits with an explanation")
	DirAccess.remove_absolute(SaveData.SAVE_PATH + ".tmp")
	main.find_child("DeckSaveButton", true, false).pressed.emit()
	await process_frame
	check(main.save_data.last_deck == 1 and main.save_data.deck_presets[1].name == "재시도 덱" and main.save_data.goals.get("edit_deck", false), "deck retry saves and activates the preset and goal together")
	print("helper_settings_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
