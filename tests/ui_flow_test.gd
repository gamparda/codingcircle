extends SceneTree

var failures := 0
var checks := 0

func expect_true(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func find_button(node: Node, text_fragment: String) -> Button:
	if node is Button and String(node.text).contains(text_fragment):
		return node
	for child in node.get_children():
		var found := find_button(child, text_fragment)
		if found != null:
			return found
	return null

func tree_text(node: Node) -> String:
	var output := String(node.text) if node is Label or node is Button else ""
	for child in node.get_children():
		output += "\n" + tree_text(child)
	return output

func key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	expect_true(tree_text(main).contains("v%s" % main.build_version()), "main menu reads the configured build version")
	for required_button in ["온라인 아레나", "AI 캠페인", "AI 연습", "덱 편성", "전적", "설정"]:
		expect_true(find_button(main, required_button) != null, "main menu exposes %s" % required_button)
	main._build_deck_screen()
	await process_frame
	var deck_text := tree_text(main)
	for required_card in ["탱커", "검사", "궁수", "마법사", "방벽", "점프대", "늪", "포탑", "발전기"]:
		expect_true(deck_text.contains(required_card), "deck editor exposes %s" % required_card)
	expect_true(deck_text.contains("선택됨"), "selected deck cards have an explicit selected marker")
	expect_true(deck_text.contains("선택 가능"), "unselected deck cards have an explicit available marker")

	main._build_settings_screen()
	await process_frame
	var bgm_slider := main.find_child("BGMVolumeSlider", true, false) as HSlider
	expect_true(bgm_slider != null, "settings expose a named BGM volume slider")
	if bgm_slider != null:
		bgm_slider.value = 0.25
		await process_frame
		var bgm_bus := AudioServer.get_bus_index("BGM")
		expect_true(bgm_bus >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(bgm_bus), linear_to_db(0.25)), "BGM slider previews volume immediately")
	expect_true(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 0)) == 1, "window scaling uses linear canvas texture filtering")
	expect_true(main.has_method("_input"), "main handles global fullscreen and cancel shortcuts")
	if main.has_method("_input"):
		var was_fullscreen := bool(main.save_data.settings.fullscreen)
		main._input(key_event(KEY_F11))
		expect_true(bool(main.save_data.settings.fullscreen) != was_fullscreen, "F11 toggles the saved fullscreen setting")
		main._input(key_event(KEY_F11))
		expect_true(bool(main.save_data.settings.fullscreen) == was_fullscreen, "a second F11 restores the previous fullscreen setting")

	main._start_local_ai_battle()
	await process_frame
	main.battle_view.selected_structure = "wall"
	if main.has_method("_input"):
		main._input(key_event(KEY_ESCAPE))
	expect_true(main.battle_view.selected_structure.is_empty(), "Escape cancels structure placement")
	main.local_model.winner = 0
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	var back_button := find_button(main, "단계 선택")
	expect_true(back_button != null, "AI result overlay provides a stage-selection button")
	expect_true(main.has_method("_exit_battle_to_menu"), "result flow exposes a menu return action")
	if back_button != null:
		back_button.pressed.emit()
		await process_frame
		await process_frame
		expect_true(find_button(main, "01  입문") != null, "AI result back action returns to the practice stage selection")
		expect_true(not main.battle_active and not main.local_ai_mode, "AI stage-selection action clears battle state")

	main._on_match_found(0)
	await process_frame
	main.battle_view.selected_structure = "turret"
	expect_true(main.has_method("_on_structure_placement_result"), "battle UI handles authoritative structure placement results")
	if main.has_method("_on_structure_placement_result"):
		main._on_structure_placement_result(false, "자원이 부족합니다.")
		expect_true(main.battle_view.selected_structure == "turret", "failed online placement keeps the selected structure")
		expect_true(main.placement_status_label.text == "자원이 부족합니다.", "failed online placement shows the server reason")
		main._on_structure_placement_result(true, "")
		expect_true(main.battle_view.selected_structure.is_empty(), "successful online placement clears the selected structure")
		expect_true(main.placement_status_label.text == "설치 완료", "success text appears only after server confirmation")
	var finished := BattleModel.new().snapshot()
	finished.winner = 0
	main._on_snapshot(finished)
	await process_frame
	expect_true(find_button(main, "재경기 준비") != null, "online result overlay is visible")
	var restarted := BattleModel.new().snapshot()
	main._on_snapshot(restarted)
	await process_frame
	expect_true(find_button(main, "재경기 준비") == null, "online rematch snapshot dismisses the old result overlay")

	var stats_button := find_button(main, "유닛 스탯")
	expect_true(stats_button != null, "battle UI exposes a unit stats panel button")
	if stats_button != null:
		stats_button.pressed.emit()
		await process_frame
		var stats_panel := main.find_child("UnitStatsPanel", true, false)
		expect_true(stats_panel != null, "unit stats button opens the detailed panel")
		if stats_panel != null:
			var stats_text := tree_text(stats_panel)
			for required in ["탱커", "마법사", "궁수", "검사", "체력", "공격력", "회복량", "DPS", "공격 간격", "사거리", "이동", "구조물", "기지 체력"]:
				expect_true(stats_text.contains(required), "stats panel exposes %s" % required)
	main.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: %d UI flow checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d UI flow checks" % [failures, checks])
		quit(1)