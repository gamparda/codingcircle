extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func click_control(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move)
	check(root.gui_get_hovered_control() == control, "pointer targets " + control.name)
	var down := InputEventMouseButton.new()
	down.position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	down.pressed = true
	root.push_input(down)
	var up := InputEventMouseButton.new()
	up.position = point
	up.button_index = MOUSE_BUTTON_LEFT
	up.button_mask = 0
	up.pressed = false
	root.push_input(up)

func run() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.save_data.tutorial_completed = false
	main._start_local_ai_battle()
	await process_frame
	check(main.find_child("FirstBattleGuide", true, false) != null, "first battle guide is visible")
	var stats := main.find_child("UnitStatsButton", true, false) as Button
	var leave := main.find_child("ExitAIBattleButton", true, false) as Button
	check(stats != null and leave != null, "both battle actions exist")
	if stats != null and leave != null:
		click_control(stats)
		await process_frame
		check(main.find_child("UnitStatsPanel", true, false) != null, "physical click opens unit stats")
		main._dismiss_stats_panel()
		await process_frame
		var portrait := main.find_child("BattleUnitPortrait", true, false) as Sprite2D
		if portrait != null:
			var unit_card := portrait.get_parent() as Button
			main.local_model.resources[0] = 150.0
			click_control(unit_card)
			check(main.local_model.resources[0] < 150.0, "unit portrait does not intercept spawning clicks")
		else:
			check(false, "battle unit portrait exists")
		if not main.structure_buttons.is_empty():
			var structure_card: Button = main.structure_buttons[0]
			click_control(structure_card)
			check(structure_card.button_pressed and not main.battle_view.selected_structure.is_empty(), "structure emblem does not intercept selection")
			click_control(structure_card)
			check(not structure_card.button_pressed and main.battle_view.selected_structure.is_empty(), "second click cancels structure selection")
		click_control(leave)
		await process_frame
		check(not main.battle_active, "physical click exits AI battle")
	main._on_match_found(0)
	await process_frame
	var online_stats := main.find_child("UnitStatsButton", true, false) as Button
	check(online_stats != null, "online match shows the stats action")
	if online_stats != null:
		click_control(online_stats)
		await process_frame
		check(main.find_child("UnitStatsPanel", true, false) != null, "physical click opens online unit stats")
	main.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: battle buttons receive pointer clicks")
	quit(1 if failures else 0)
