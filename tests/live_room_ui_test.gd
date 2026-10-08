extends SceneTree
## Lobby list screen: filter chips and the live-battle details on room cards.

const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
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
	main.save_data = SaveData.default_data()
	MultiplayerUI.browser(main)
	await process_frame
	var chips: Array = main.find_child("RoomFilters", true, false).get_children()
	check(chips.size() == 3 and main.find_child("RoomFilter_all", true, false).button_pressed, "three filter chips, the full list selected")
	main.lobby_filter = "live"
	MultiplayerUI.browser(main)
	await process_frame
	check(main.find_child("RoomFilter_live", true, false).button_pressed and not main.find_child("RoomFilter_all", true, false).button_pressed, "the chosen filter is remembered when the screen is rebuilt")
	var live := {"names": ["알파", "베타"], "elapsed": 75.0, "units": [["shield", "archer", "healer"], ["berserker", "warlock", "necromancer"]]}
	var data := {"rooms": [{"code": "ABC234", "name": "빠른 대전", "players": 2, "locked": false, "state": "playing", "spectators": 3, "live": live},
		{"code": "DEF567", "name": "친선", "players": 2, "locked": true, "state": "playing", "spectators": 0},
		{"code": "GHJ789", "name": "대기방", "players": 1, "locked": false, "state": "waiting", "spectators": 0}], "page": 0, "total": 3}
	main._render_room_listing(data)
	await process_frame
	var info = main.find_child("RoomLiveInfo", true, false)
	check(info != null and info.get_child(0).text.contains("알파") and info.get_child(0).text.contains("01:15"), "a running public battle shows both names and the elapsed time")
	check(info.get_children().filter(func(node): return node is TextureRect).size() == 6, "and both decks as portraits")
	check(main.find_children("RoomLiveInfo", "HBoxContainer", true, false).size() == 1, "locked and waiting rooms show no live details")
	check(main.find_children("WatchRoomButton", "Button", true, false).size() >= 1, "rooms keep their watch buttons")
	print("live_room_ui_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
