extends SceneTree
## The 계산 돕기 section of the settings screen and its saved values.

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var save := SaveData.default_data()
	check(not save.settings.helper_enabled and save.settings.helper_token == "" and save.settings.helper_cores == 1, "helping is off by default")
	var stored := SaveData.sanitize(JSON.parse_string(JSON.stringify({"settings": {"helper_enabled": true, "helper_token": "  abc  ", "helper_cores": 5, "language": "ko"}})))
	check(stored.settings.helper_enabled and stored.settings.helper_token == "abc" and stored.settings.helper_cores == 5, "the values survive saving")
	var junk := SaveData.sanitize({"settings": {"helper_enabled": "yes", "helper_token": 5, "helper_cores": 9999}})
	check(not junk.settings.helper_enabled and junk.settings.helper_token == "" and junk.settings.helper_cores == 64, "junk is dropped or clamped")
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main._build_settings_screen()
	await process_frame
	for node_name in ["HelperToggle", "HelperToken", "HelperCores", "HelperCoresLabel"]:
		check(main.find_child(node_name, true, false) != null, "settings has %s" % node_name)
	check(main.find_child("HelperToken", true, false).secret, "the token is hidden")
	main.find_child("HelperToggle", true, false).button_pressed = true
	main.find_child("HelperToken", true, false).text = "geheim"
	main.find_child("HelperCores", true, false).value = 1
	main.find_child("SettingsSaveButton", true, false).pressed.emit()
	await process_frame
	check(main.save_data.settings.helper_enabled and main.save_data.settings.helper_token == "geheim" and main.save_data.settings.helper_cores == 1, "saving the settings stores them")
	check(main.helper_service == null, "headless runs never start the service")
	print("helper_settings_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
