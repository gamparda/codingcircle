extends SceneTree
## Battle cards follow cheats and run boons: a lifted one-of-a-kind limit lets more demon lords out, and a
## price boon (징병관) shows on the card.

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void: call_deferred("run")
func run() -> void:
	var bootstrap := Control.new(); bootstrap.name = "Bootstrap"; root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate(); bootstrap.add_child(main); main.updater.enabled = false
	main.save_data = SaveData.default_data(); main.save_data.tutorial_completed = true
	main.save_data.deck_presets[main.save_data.get("last_deck", 0)].units = ["shield", "paladin", "sniper", "demon_lord"]
	await process_frame
	main._build_connect_screen()
	await process_frame
	preload("res://scripts/screens/EndlessFlow.gd").start(main)
	for i in 5: await process_frame
	var Cheats = load("res://scripts/Cheats.gd")
	for a in ["resources", "cooldowns", "no_cap"]: Cheats.perform(main.local_model, 0, a)
	var lord: Button = null
	var paladin: Button = null
	for b in main.purchase_buttons:
		if b.get_meta("unit_kind", "") == "demon_lord": lord = b
		if b.get_meta("unit_kind", "") == "paladin": paladin = b
	for i in 3:
		main.local_model.tick(1.0/30.0)
		main._on_snapshot(main.local_model.snapshot())
		await process_frame
		check(not lord.disabled, "the demon lord card stays usable with the limit lifted")
		lord.pressed.emit()
		await process_frame
	check(main.local_model.units.filter(func(u): return u.kind == "demon_lord").size() == 3, "three demon lords on the field")
	var director = main.endless_run.director
	director.boons.append("recruiter")
	main.local_model.modifiers[0] = load("res://scripts/run/RunBoons.gd").combine(director.boons)
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	check(float(paladin.get_meta("purchase_cost")) == main.local_model.unit_cost(0, "paladin") and paladin.get_node("CostBadge").text == str(int(main.local_model.unit_cost(0, "paladin"))) and main.local_model.unit_cost(0, "paladin") < 65.0, "the card shows the boon price")
	Cheats.perform(main.local_model, 0, "army_cap")
	check(main.local_model.side_limit(0) == 2 * BattleModel.SIDE_UNIT_LIMIT, "the solo cheat doubles the unit limit")
	check(not load("res://scripts/Cheats.gd").SOLO_ONLY.is_empty(), "the doubled limit stays out of online battles")
	print("cheat_ui_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
