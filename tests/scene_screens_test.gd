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

	var UIKit = load("res://scripts/ui/UIKit.gd")
	check(UIKit.display_font() is FontFile, "bundled display font is imported and loadable")
	for path in ["res://scenes/ui/SubMenuFrame.tscn", "res://scenes/ui/PatchNotesScreen.tscn", "res://scenes/ui/RecordsScreen.tscn"]:
		check(load(path) is PackedScene, "%s loads as a scene" % path)

	var rule: String = preload("res://scripts/ServerStats.gd").ruleset_id()
	main.save_data.daily = {
		"20261010": {"won": true, "score": 1000, "seconds": 60.0, "ruleset": rule, "previous": {}},
		"20261011": {"won": true, "score": 2000, "seconds": 80.0, "ruleset": "older", "previous": {
			rule: {"won": true, "score": 720, "seconds": 90.0, "ruleset": rule},
			"0": {"won": false, "score": 0, "seconds": 0.0, "ruleset": "0"}}}}
	main.save_data.weekly = {"20261005": {"won": true, "score": 1500, "seconds": 70.0, "ruleset": "0", "previous": {}}}
	var before := JSON.stringify(main.save_data)
	main._build_records_screen()
	await process_frame
	var records = main.find_child("RecordsScreen", true, false)
	check(records != null and records.size == Vector2(1060, 650), "records screen is the scene with its declared 1060x650 frame")
	check(main.find_child("RecordsCard_AI", true, false) != null and main.find_child("RecordsCard_온라인", true, false) != null, "records show a card for AI and for online play")
	var table := main.find_child("CampaignTable", true, false) as GridContainer
	check(table != null and table.get_child_count() == table.columns * (ServerAI.MAX_STAGE + 1), "the campaign table has a header row and one row per stage")
	check(records.get_node("Column/Title").text == "개인 전적", "title comes through the shared frame")
	check(records.get_node("Column").get_child(records.get_node("Column").get_child_count() - 1).name == "RecordsFooter", "footer actions follow the content")
	var daily_tab: Button = main.find_child("RecordsTab_daily", true, false)
	daily_tab.button_pressed = true
	daily_tab.pressed.emit()
	await process_frame
	var daily_page: VBoxContainer = main.find_child("RecordsPage_daily", true, false)
	var daily_table: GridContainer = main.find_child("ChallengeHistoryTable_daily", true, false)
	var filter: OptionButton = main.find_child("ChallengeHistoryFilter", true, false)
	check(daily_page.is_visible_in_tree() and filter.is_visible_in_tree() and not table.is_visible_in_tree(), "daily tab opens the challenge history and version selector")
	check(daily_table.get_child_count() == 30 and daily_table.get_child(6).text == "2026-10-11", "history lists all preserved versions with the newest UTC date first")
	check(daily_table.get_child(7).text == "현재 · " + rule and daily_table.get_child(9).text == "720점" and daily_table.get_child(10).text == "90.0초", "current records are displayed first even when archived under previous")
	check(daily_table.get_child(13).text == "버전 미상 · 0" and daily_table.get_child(14).text == "실패" and daily_table.get_child(16).text == "0.0초", "unknown versions and legitimate zero-time failures remain visible")
	filter.select(1)
	filter.item_selected.emit(1)
	await process_frame
	daily_table = main.find_child("ChallengeHistoryTable_daily", true, false)
	check(daily_table.get_child_count() == 18 and daily_table.get_child(15).text == "1000점", "current-only filter preserves separate daily best scores")
	filter.select(2)
	filter.item_selected.emit(2)
	await process_frame
	daily_table = main.find_child("ChallengeHistoryTable_daily", true, false)
	check(daily_table.get_child_count() == 18 and daily_table.get_child(13).text == "이전 · older", "previous-version filter excludes current scores")
	var weekly_tab: Button = main.find_child("RecordsTab_weekly", true, false)
	weekly_tab.button_pressed = true
	weekly_tab.pressed.emit()
	await process_frame
	var weekly_table: GridContainer = main.find_child("ChallengeHistoryTable_weekly", true, false)
	check(weekly_table.is_visible_in_tree() and weekly_table.get_child_count() == 12 and weekly_table.get_child(6).text == "2026-10-05", "weekly history uses its own stored week-start date and score")
	filter.select(1)
	filter.item_selected.emit(1)
	await process_frame
	var empty: Label = main.find_child("ChallengeHistoryEmpty_weekly", true, false)
	check(empty != null and empty.is_visible_in_tree(), "an empty version selection has a visible explanation")
	check(JSON.stringify(main.save_data) == before, "viewing and filtering records does not modify progress or submissions")
	check(main.find_child("RecordsScroll", true, false) is ScrollContainer and main.find_child("RecordsBackButton", true, false).get_parent().get_parent() == records.column, "history scrolls while footer actions remain outside it")

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
	check(deck_panel != null and deck_panel.scene_file_path == "res://scenes/ui/DeckScreen.tscn" and deck_panel.find_child("DeckSaveButton", true, false) is Button and deck_panel.find_child("Tabs", true, false).get_child_count() == 3, "deck editor is the DeckScreen scene with its skeleton declared in the .tscn")
	print("scene_screens_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
