extends SceneTree
## Touch layout: every visible button on the main screens must be big enough for a finger.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MIN_HEIGHT := 56.0
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func audit(main, label: String) -> void:
	await process_frame
	await process_frame
	var small: Array = []
	for node in main.find_children("*", "BaseButton", true, false):
		if not node.is_visible_in_tree() or node is OptionButton:
			continue
		if node.size.y > 0.0 and node.size.y < MIN_HEIGHT and node.size.x > 0.0:
			small.append("%s(%s %.0fx%.0f)" % [node.name, node.get("text"), node.size.x, node.size.y])
	check(small.is_empty(), "%s has buttons too small to tap: %s" % [label, small])

func _init() -> void:
	call_deferred("run")

func run() -> void:
	UIKit.force_touch = true
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	main.save_data.tutorial_completed = true
	await audit(main, "main menu")
	main._build_ai_stage_screen(true)
	await audit(main, "campaign")
	main._build_deck_screen()
	await audit(main, "deck editor")
	main._build_settings_screen(true)
	await audit(main, "settings")
	main._build_records_screen()
	await audit(main, "records")
	main._build_replay_list()
	await audit(main, "replay list")
	main._build_lobby_screen()
	main.network.client_connection_state = "lobby"
	main._on_room_list({"rooms": [{"code": "ABC233", "name": "방", "players": 1, "state": "waiting"}], "page": 0, "total": 1})
	await audit(main, "lobby")
	main.campaign_mode = true
	main._start_local_ai_battle(2)
	await audit(main, "battle")
	print("touch_layout_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
