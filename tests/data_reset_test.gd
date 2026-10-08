extends SceneTree
## "데이터 전체 초기화": what is deleted, what is kept, the locked confirm button and the settings entry.

const DataReset = preload("res://scripts/DataReset.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _touch(path: String, text: String = "x") -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var real_save_exists := FileAccess.file_exists(SaveData.SAVE_PATH)
	var real_save_time := FileAccess.get_modified_time(SaveData.SAVE_PATH) if real_save_exists else 0
	var base := "user://data_reset_test"
	DirAccess.make_dir_recursive_absolute(base + "/replays/nested")
	DirAccess.make_dir_recursive_absolute(base + "/content")
	DataReset.save_path = base + "/save.json"
	BattleReplay.save_dir = base + "/replays"
	MetaStats.cache_path = base + "/meta.json"
	_touch(DataReset.save_path, "{}")
	_touch(DataReset.save_path + ".tmp")
	_touch(MetaStats.cache_path)
	_touch(base + "/replays/a.json")
	_touch(base + "/replays/b.json")
	_touch(base + "/replays/nested/c.json")
	_touch(base + "/content/pack.pck") # downloaded content is not player data
	_touch(base + "/unrelated.txt")
	MetaStats.snapshot = {"ruleset": "x"}
	MetaStats.boards = {"20260101": {}}

	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.nickname = "지울 닉네임"
	main.save_data.tutorial_completed = true
	main.save_data.stats.ai_wins = 9
	main.save_data.achievements = {"first_win": 1}
	main.network.client_nickname = "지울 닉네임"

	# The settings screen offers it and the confirm screen starts locked.
	main._build_settings_screen()
	await process_frame
	check(main.find_child("DataResetButton", true, false) != null, "the settings screen has the reset button")
	DataReset.countdown_seconds = 2
	main.find_child("DataResetButton", true, false).pressed.emit()
	await process_frame
	var confirm: Button = main.find_child("ConfirmDataReset", true, false)
	check(confirm != null and confirm.disabled and confirm.text.contains("(2)"), "the confirm button is locked at first")
	check(FileAccess.file_exists(DataReset.save_path), "nothing is deleted just by opening the screen")
	main.find_child("CancelDataReset", true, false).pressed.emit()
	await process_frame
	check(FileAccess.file_exists(DataReset.save_path) and main.save_data.stats.ai_wins == 9, "cancelling keeps everything")

	# With no countdown the button works and wipes the player's data only.
	DataReset.countdown_seconds = 0
	DataReset.show_confirm(main)
	await process_frame
	confirm = main.find_child("ConfirmDataReset", true, false)
	check(not confirm.disabled, "the confirm button unlocks")
	confirm.pressed.emit()
	await process_frame
	check(not FileAccess.file_exists(DataReset.save_path) and not FileAccess.file_exists(DataReset.save_path + ".tmp") and not FileAccess.file_exists(MetaStats.cache_path), "save file, its temp file and the statistics cache are gone")
	check(not DirAccess.dir_exists_absolute(base + "/replays"), "the replay folder is gone, nested folders included")
	check(FileAccess.file_exists(base + "/content/pack.pck") and FileAccess.file_exists(base + "/unrelated.txt"), "content packs and other files are left alone")
	check(main.save_data.stats.ai_wins == 0 and main.save_data.achievements.is_empty() and not bool(main.save_data.tutorial_completed) and main.save_data.nickname == "플레이어", "the in-memory data is back to defaults")
	check(main.network.client_nickname == "플레이어" and MetaStats.snapshot.is_empty() and MetaStats.boards.is_empty(), "the nickname and statistics caches are reset too")
	check(main.find_child("SettingsSaveButton", true, false) == null and main.find_child("MultiplayerButton", true, false) != null, "the game returns to the main menu")
	check(main.status_label.text.contains("초기화했습니다"), "and says what happened")
	check(FileAccess.file_exists(SaveData.SAVE_PATH) == real_save_exists and (not real_save_exists or FileAccess.get_modified_time(SaveData.SAVE_PATH) == real_save_time), "the real save file was never touched by this test")
	# Wiping again with nothing there is harmless.
	var again := DataReset.wipe(main)
	check(int(again.files) == 0 and int(again.replays) == 0, "wiping an already empty device is a no-op")
	DirAccess.remove_absolute(base + "/content/pack.pck")
	DirAccess.remove_absolute(base + "/content")
	DirAccess.remove_absolute(base + "/unrelated.txt")
	DirAccess.remove_absolute(base)
	BattleReplay.save_dir = "user://replays"
	print("data_reset_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
