extends SceneTree
## Replay viewer extras: loop segment, unit inspector, zoom and pan, and that the bottom row still fits.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _replay() -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	model.configure_deck(1, ServerAI.stage_unit_deck(3), ServerAI.stage_structure_deck(3))
	var ai := ServerAI.new(1, 3)
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": 3}, {"mode": "campaign", "stage": 3})
	var tick := 0
	while model.winner == -1 and tick < 30 * 200:
		if tick % 45 == 0 and model.spawn_unit(0, "swordsman"):
			recorder.on_spawn(0, "swordsman")
		ai.update(model, 1.0 / 30.0)
		model.tick(1.0 / 30.0)
		recorder.on_tick()
		tick += 1
	return recorder.finish(model)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var replay := _replay()
	BattleReplay.save_dir = "user://replay_viewer_plus_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main._play_replay(BattleReplay.save(replay, "plus"))
	await process_frame
	var viewer = main.replay_viewer
	viewer.toggle_pause()

	# Loop segment.
	viewer.seek(300)
	check(not viewer.set_loop_end() and viewer.loop_end == -1, "an end mark needs a start before it")
	check(not viewer.toggle_loop() and not viewer.loop_enabled, "looping needs both marks")
	viewer.set_loop_start()
	viewer.seek(300 + 60)
	check(viewer.set_loop_end() and viewer.loop_start == 300 and viewer.loop_end == 360 and viewer.loop_ready(), "start and end marks are stored")
	viewer.seek(330)
	viewer.set_loop_end()
	check(viewer.loop_end == 330, "the end mark can be moved")
	viewer.seek(300)
	check(not viewer.set_loop_end() and viewer.loop_end == 330, "an end that is not after the start is refused")
	viewer.seek(345)
	viewer.set_loop_start()
	check(viewer.loop_start == 345 and viewer.loop_end == -1 and not viewer.loop_ready(), "moving the start past the end drops the end")
	viewer.seek(300)
	viewer.set_loop_start()
	viewer.seek(360)
	viewer.set_loop_end()
	viewer.seek(330)
	check(viewer.toggle_loop() and viewer.loop_enabled, "looping turns on with a valid segment")
	viewer.toggle_pause()
	var wrapped := false
	for i in 40:
		viewer._process(0.1)
		if viewer.player.ticks < 330 and viewer.player.ticks >= 295:
			wrapped = true
		check(viewer.player.ticks <= 361, "the playhead never runs past the end mark (%d)" % viewer.player.ticks)
	check(wrapped, "playback wraps back to the start mark")
	viewer.toggle_pause()
	check(not viewer.toggle_loop() and not viewer.loop_enabled, "looping can be switched off")
	check(viewer.graph.loop_start == 300 and viewer.graph.loop_end == 360 and not viewer.graph.loop_on, "the timeline shows the segment")

	# Zoom and pan.
	var battlefield = viewer.view
	check(battlefield.view_zoom == 1.0 and battlefield.view_offset == Vector2.ZERO and not viewer.zoom_reset_button.visible, "the view starts unzoomed")
	var anchor := Vector2(640, 300)
	battlefield.zoom_at(anchor, 2.0)
	check(is_equal_approx(battlefield.view_zoom, 2.0) and viewer.zoom_reset_button.visible, "zooming works and offers the reset button")
	check(battlefield.to_view(anchor).distance_to(anchor) < 0.01, "the point under the cursor stays put")
	battlefield.zoom_at(anchor, 9.0)
	check(is_equal_approx(battlefield.view_zoom, BattleView.ZOOM_MAX), "zoom is capped")
	battlefield.zoom_at(anchor, 0.1)
	check(is_equal_approx(battlefield.view_zoom, BattleView.ZOOM_MIN) and battlefield.view_offset == Vector2.ZERO and not viewer.zoom_reset_button.visible, "zooming out fully restores the plain view")
	battlefield.zoom_at(Vector2(0, 0), 2.0)
	battlefield.view_offset += Vector2(500, 500)
	battlefield._clamp_offset()
	check(battlefield.view_offset == Vector2.ZERO, "panning cannot leave the field on the near side")
	battlefield.view_offset = Vector2(-99999, -99999)
	battlefield._clamp_offset()
	check(battlefield.view_offset.x >= battlefield.size.x * -1.0 - 0.01 and battlefield.view_offset.y >= battlefield.size.y * -1.0 - 0.01, "nor on the far side")
	battlefield.reset_view()
	check(battlefield.view_zoom == 1.0 and battlefield.view_offset == Vector2.ZERO and not viewer.zoom_reset_button.visible, "reset returns to 1x")

	# Unit inspector.
	viewer.seek(500)
	var units: Array = battlefield.snapshot.get("units", [])
	check(not units.is_empty(), "there are units on the field to inspect")
	var unit: Dictionary = units[0]
	var lane_y: float = battlefield.size.y * 0.72
	var click: Vector2 = Vector2(battlefield.world_to_screen_x(float(unit.x)), lane_y - 40.0)
	check(int(battlefield.unit_at(click).get("id", -1)) == int(unit.id), "a click on a unit finds it")
	check(battlefield.unit_at(Vector2(click.x, 5.0)).is_empty(), "a click on empty sky finds nothing")
	var seen := []
	battlefield.unit_clicked.connect(func(clicked): seen.append(clicked))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = click
	press.pressed = false
	battlefield._gui_input(press)
	check(seen.size() == 1 and int(seen[0].id) == int(unit.id) and viewer.unit_panel.visible, "clicking a unit opens the panel")
	check(viewer.panel_name.text == String(BattleModel.UNIT_NAMES[unit.kind]) and viewer.panel_hp.text.contains("/"), "the panel names the unit and shows its health")
	check(viewer.unit_panel.position.x >= 0.0 and viewer.unit_panel.position.x + 250.0 <= 1280.0, "the panel stays on screen")
	battlefield.zoom_at(click, 2.0)
	var zoomed_click: Vector2 = battlefield._view_transform() * Vector2(battlefield.world_to_screen_x(float(unit.x)), lane_y - 40.0)
	check(int(battlefield.unit_at(zoomed_click).get("id", -1)) == int(unit.id), "hit-testing accounts for zoom")
	battlefield.reset_view()
	viewer.close_inspector()
	check(not viewer.unit_panel.visible, "the panel closes on demand")
	viewer._on_unit_clicked(unit)
	viewer.close_inspector()
	viewer._on_unit_clicked({})
	check(not viewer.unit_panel.visible, "clicking empty ground closes the panel")
	viewer._on_unit_clicked(unit)
	viewer.seek(0)
	check(not viewer.unit_panel.visible and viewer.inspected_id == -1, "the panel closes when the unit no longer exists")
	var normal := BattleView.new()
	normal.size = Vector2(1280, 492)
	var clicks := []
	normal.battlefield_clicked.connect(func(world_x): clicks.append(world_x))
	normal._gui_input(press)
	check(clicks.size() == 1 and not normal.inspect_mode, "outside the viewer, clicks still reach the battlefield signal")

	# The bottom row still fits.
	var row = viewer.find_child("ReplayNoteInput", true, false).get_parent()
	var previous_right := -1.0
	var fits := true
	for child in row.get_children():
		var rect: Rect2 = child.get_rect()
		fits = fits and rect.position.x >= previous_right - 0.5 and rect.end.x <= row.size.x + 0.5
		previous_right = rect.end.x
	check(fits, "the control row has no overlaps and no overflow")
	var loop_row = viewer.find_child("ReplayLoopRow", true, false)
	check(loop_row.position.x >= viewer.graph.position.x + viewer.graph.size.x and loop_row.position.x + loop_row.size.x <= 1280.0, "the loop buttons sit beside the timeline")
	for file in BattleReplay.list_saved():
		DirAccess.remove_absolute(file)
	DirAccess.remove_absolute("user://replay_viewer_plus_test")
	print("replay_viewer_plus_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
