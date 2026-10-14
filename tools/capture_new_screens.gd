extends SceneTree
## Visual QA for the screens added by the autonomous rounds. Needs a real renderer (not --headless).
##   godot --path . --script res://tools/capture_new_screens.gd -- --out=C:/some/dir [--touch]

var out_dir := "user://captures_new"
const BattleReplay = preload("res://scripts/BattleReplay.gd")
var main

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--touch":
			preload("res://scripts/ui/UIKit.gd").force_touch = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("run")

func shot(name: String, frames: int = 4) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])

func click(path_name: String) -> bool:
	var button := main.find_child(path_name, true, false) as BaseButton
	if button == null or button.disabled:
		return false
	button.pressed.emit()
	return true

func run() -> void:
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bootstrap)
	main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	main.save_data.tutorial_completed = true
	var rule: String = preload("res://scripts/ServerStats.gd").ruleset_id()
	main.save_data.daily = {
		"20261013": {"won": true, "score": 2100, "seconds": 62.5, "ruleset": rule, "previous": {}},
		"20261012": {"won": true, "score": 1800, "seconds": 80.0, "ruleset": rule, "previous": {"older": {"won": true, "score": 2400, "seconds": 70.0, "ruleset": "older"}}},
		"20261011": {"won": false, "score": 0, "seconds": 41.0, "ruleset": "0", "previous": {}}}
	main.save_data.weekly = {"20261012": {"won": true, "score": 2300, "seconds": 75.0, "ruleset": rule, "previous": {}}}

	# Records: challenge history with its search tools and the new archived-battle column.
	main._build_records_screen()
	await shot("01_records_campaign")
	click("RecordsTab_daily")
	await shot("02_records_daily")

	# Settings -> data page holds the profile backup / recovery entry.
	main._build_settings_screen()
	await shot("03_settings")
	var recovery = load("res://scripts/screens/ProfileRecovery.gd")
	recovery.show(main)
	await shot("04_profile_recovery", 6)
	main._dismiss_action_overlay()

	# Replay shelf with a few recorded battles.
	main.campaign_mode = true
	main._start_local_ai_battle(2)
	for i in 30:
		await process_frame
	await shot("05_battle_intro", 2)
	for i in 200:
		await process_frame
	main._purchase_unit(main.battle_preset.units[0])
	for i in 90:
		await process_frame
	await shot("06_battle")
	# Structure card selection shows the build cursor, spacing bands and lifetime labels.
	if main.structure_buttons.size() > 0:
		main.local_model.resources[0] = 400.0
		main._refresh_purchase_buttons(400.0)
		main.structure_buttons[min(1, main.structure_buttons.size() - 1)].pressed.emit()
		for i in 6:
			await process_frame
		await shot("07_build_cursor")
		main.battle_view.selected_structure = ""
	main._show_army_panel(0)
	await shot("08_army_panel", 6)
	main._dismiss_action_overlay()
	main._show_structure_panel()
	await shot("09_structure_panel", 6)
	main._dismiss_action_overlay()
	main._show_stats_panel()
	await shot("10_stats", 6)
	main._dismiss_stats_panel()
	main.local_model.winner = 0
	main._on_snapshot(main.local_model.snapshot())
	await shot("11_result", 10)
	# Open the battle summary from the result screen when the button exists.
	for name in ["ShowBattleReport", "BattleReportButton", "ReportButton"]:
		if click(name):
			await shot("12_result_summary", 8)
			break
	main._exit_ai_battle()
	main._build_replay_list()
	for i in 60:
		await process_frame
	await shot("13_replay_shelf", 6)
	var saved: Array = BattleReplay.list_saved()
	if not saved.is_empty():
		main._play_replay(saved[0])
		for i in 90:
			await process_frame
		await shot("14_replay_viewer", 6)
		var viewer = main.find_child("ReplayViewer", true, false)
		if viewer != null and viewer.has_method("show_report"):
			viewer.show_report()
			await shot("15_replay_report", 8)
	print("CAPTURES_DONE ", out_dir)
	quit(0)
