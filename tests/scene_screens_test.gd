extends SceneTree
## Screens that live in .tscn files: layout comes from the scene, data from code.

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame

	for path in ["res://scenes/ui/SubMenuFrame.tscn", "res://scenes/ui/PatchNotesScreen.tscn", "res://scenes/ui/RecordsScreen.tscn"]:
		check(load(path) is PackedScene, "%s loads as a scene" % path)

	main._build_records_screen()
	await process_frame
	var records = main.find_child("RecordsScreen", true, false)
	check(records != null and records.size == Vector2(1060, 650), "records screen is the scene with its declared 1060x650 frame")
	check(main.find_child("Summary", true, false).text.contains("AI") and main.find_child("Summary", true, false).text.contains("온라인"), "records summary is filled from save data")
	check(main.find_child("CampaignRecords", true, false).text.split("\n").size() == ServerAI.MAX_STAGE, "one record line per campaign stage")
	check(records.get_node("Column/Title").text == "개인 전적", "title comes through the shared frame")
	check(records.get_node("Column").get_child(records.get_node("Column").get_child_count() - 1) is Button, "back button follows the content")

	main._build_patch_notes_screen()
	await process_frame
	var entries = main.find_child("Entries", true, false)
	check(entries != null and entries.get_child_count() > 3, "patch notes populate the scene's entry list")
	check(main.find_child("PatchNotesScroll", true, false) is ScrollContainer and main.find_child("PatchNotesBack", true, false) is Button, "patch note scroll and back button keep their names")

	# Code-built screens share the same scene frame through _submenu.
	main._build_settings_screen()
	await process_frame
	var settings_frame = main.find_child("SubMenuFrame", true, false)
	check(settings_frame != null and settings_frame.scene_file_path == "res://scenes/ui/SubMenuFrame.tscn", "settings reuses the SubMenuFrame scene")
	main._build_deck_screen()
	await process_frame
	var deck_panel = main.find_child("DeckPanel", true, false)
	check(deck_panel != null and deck_panel.scene_file_path == "res://scenes/ui/SubMenuFrame.tscn", "deck editor is a (resized) SubMenuFrame scene instance")
	print("scene_screens_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
