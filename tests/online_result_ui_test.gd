extends SceneTree
## Online result screen: opponent card (nickname + deck) and the player's record summary.

const Store = preload("res://scripts/RoomSessions.gd")
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
	main.save_data = load("res://scripts/SaveData.gd").default_data()
	main.save_data.stats.online_completed = 12
	main.save_data.stats.online_wins = 8
	main.save_data.stats.online_losses = 3
	main.save_data.stats.online_draws = 1
	var store := Store.new()
	var mine := {"units": ["shield", "swordsman", "archer"], "structures": ["wall", "swamp", "turret"]}
	var theirs := {"units": ["berserker", "warlock", "necromancer"], "structures": ["wall", "turret", "generator"]}
	store.create(1, "ABC234", "테스트방", "나", "", "", mine)
	store.join(20, "ABC234", "도전자", "player", theirs)
	main.network.client_session = store.public_state("ABC234")
	main.network.client_connection_state = "in_match"
	main.local_ai_mode = false
	main.campaign_mode = false
	main.own_side = 0
	main.battle_preset = mine
	main._build_battle_screen()
	var model := BattleModel.new()
	model.winner = 0
	main.current_snapshot = model.snapshot()
	main.result_recorded = true # the stats above stand for the totals after this match
	main._show_result(0)
	await create_timer(1.8).timeout # let the battle intro banner leave before looking
	var strip = main.result_overlay.find_child("MatchStrip", true, false)
	check(strip != null, "online result shows the match strip")
	if strip != null:
		check(main.result_overlay.find_child("OpponentName", true, false).text == "도전자", "opponent nickname is shown")
		check(main.result_overlay.find_child("RecordSummary", true, false).text.contains("8승") and main.result_overlay.find_child("RecordSummary", true, false).text.contains("3패"), "record summary shows wins and losses")
		var opponent_card: Control = main.result_overlay.find_child("OpponentCard", true, false)
		check(opponent_card.find_children("*", "TextureRect", true, false).size() == 3, "opponent deck shows three unit portraits")
		var panel: Control = main.result_overlay.find_child("ResultPanel", true, false)
		check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(panel.get_global_rect()), "taller online panel stays on screen")
		var buttons: Array = main.result_overlay.find_children("*", "Button", true, false)
		check(buttons.all(func(button): return panel.get_global_rect().encloses(button.get_global_rect())), "result buttons stay inside the panel")
	if capture_dir != "":
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("%s/online-result.png" % capture_dir)
	# Spectators see both sides but no personal record.
	main.network.client_is_spectator = true
	main._dismiss_result_overlay()
	main.result_shown = false
	main._show_result(0)
	await process_frame
	check(main.result_overlay.find_child("MatchStrip", true, false) != null and main.result_overlay.find_child("RecordCard", true, false) == null, "spectators get no personal record card")
	print("online_result_ui_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
