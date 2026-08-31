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

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	expect_true(tree_text(main).contains("v0.4.0"), "main menu reads the v0.4.0 build version")
	for required_button in ["온라인 아레나", "AI 캠페인", "AI 연습", "덱 편성", "전적", "설정"]:
		expect_true(find_button(main, required_button) != null, "main menu exposes %s" % required_button)
	main._build_deck_screen()
	await process_frame
	var deck_text := tree_text(main)
	for required_card in ["탱커", "검사", "궁수", "마법사", "방벽", "점프대", "늪", "포탑", "발전기"]:
		expect_true(deck_text.contains(required_card), "deck editor exposes %s" % required_card)

	main._start_local_ai_battle()
	await process_frame
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