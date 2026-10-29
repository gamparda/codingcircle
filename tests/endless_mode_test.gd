extends SceneTree
## Endless defense: wave plans, the wave side's missing base, wave breaks with boon picks, saving at a break,
## resuming, records, and the screen flow from the menu to the result.

const WaveDirector = preload("res://scripts/run/WaveDirector.gd")
const RunBoons = preload("res://scripts/run/RunBoons.gd")
const RunRecords = preload("res://scripts/run/RunRecords.gd")
const EndlessFlow = preload("res://scripts/screens/EndlessFlow.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func cost(entries: Array) -> float:
	var total := 0.0
	for entry in entries:
		total += float(BattleModel.UNIT_STATS[entry.kind].cost)
	return total

func run() -> void:
	# Plans.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var first := WaveDirector.plan(1, rng)
	check(not first.is_empty() and cost(first) <= WaveDirector.budget(1), "wave 1 spends at most its budget")
	check(first.all(func(entry): return WaveDirector.pool(1).has(entry.kind) and float(entry.t) <= WaveDirector.SPAWN_WINDOW), "wave 1 sends only first-tier units within the window")
	check(WaveDirector.budget(12) > WaveDirector.budget(11) and WaveDirector.growth(4) == 1.0 and WaveDirector.growth(10) > WaveDirector.growth(5) and WaveDirector.growth(5) > 1.0, "waves grow in size and strength")
	var boss := WaveDirector.plan(10, rng)
	check(boss.any(func(entry): return entry.kind == "demon_lord"), "wave 10 brings a boss")
	var early_boss := WaveDirector.plan(5, rng)
	check(String(early_boss[0].kind) == "paladin", "wave 5's boss is a paladin")
	var again := RandomNumberGenerator.new()
	again.seed = 5
	check(WaveDirector.plan(1, again) == first, "plans follow the seed")

	# A run in the model.
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "archer", "healer", "swordsman"], ["wall", "turret", "generator", "swamp"])
	var director := WaveDirector.new(11)
	director.setup(model)
	check(model.invulnerable_bases[1] and model.unit_decks[1].is_empty(), "the wave side has no base and no deck of its own")
	var dt := 1.0 / 30.0
	while director.wave == 0:
		director.update(model, dt)
		model.tick(dt)
	check(director.wave == 1 and model.combat_events.any(func(event): return String(event.get("type", "")) == "WAVE"), "the first wave begins after a short wait")
	for i in 30 * 30:
		director.update(model, dt)
		model.tick(dt)
	check(model.units.any(func(unit): return int(unit.side) == 1), "wave units arrive")
	# Clear the field: the wave is beaten and a boon is offered.
	model.units = model.units.filter(func(unit): return int(unit.side) != 1) # zombies would rise again
	director.queue.clear()
	model.tick(dt)
	var resources_before: float = model.resources[0]
	director.update(model, dt)
	check(director.awaiting_choice and director.offers.size() == 3, "a beaten wave offers three boons")
	check(model.resources[0] > resources_before or is_equal_approx(model.resources[0], model.resource_capacity(0)), "a beaten wave pays a bonus")
	check(director.waves_cleared() == 1, "one wave cleared")
	director.update(model, dt)
	check(director.awaiting_choice and director.wave == 1, "nothing happens while a boon waits to be picked")
	director.choose(model, String(director.offers[0]))
	check(not director.awaiting_choice and director.boons.size() == 1 and not model.modifiers[0].is_empty(), "the picked boon applies to the defender")
	check(model.modifiers[1].is_empty() or not model.modifiers[1].has("income"), "boons never help the waves")
	# The wave side's base never falls.
	model.base_hp[1] = 1.0
	model.units.append({"id": 9999, "side": 0, "kind": "swordsman", "hp": 50.0, "max_hp": 50.0, "damage": 500.0, "interval": 0.1, "speed": 0.0, "range": 9999.0, "x": BattleModel.FIELD_RIGHT - 5.0, "cooldown": 0.0})
	for i in 10:
		model.tick(dt)
	check(model.winner == -1 and model.base_hp[1] == 1.0, "the wave side's base cannot be destroyed")
	# Pressure: a wave left alive too long lets the next one in.
	var slow := BattleModel.new()
	slow.configure_deck(0, ["shield", "archer", "healer", "swordsman"], ["wall", "turret", "generator", "swamp"])
	var pressing := WaveDirector.new(3)
	pressing.setup(slow)
	slow.base_max_hp[0] = 100000.0
	slow.base_hp[0] = 100000.0
	while slow.elapsed < WaveDirector.INTERMISSION + WaveDirector.PRESSURE_SECONDS + 2.0:
		pressing.update(slow, dt)
		slow.tick(dt)
	check(pressing.wave >= 2 and not pressing.awaiting_choice, "an unbeaten wave does not stop the next one")

	# Records and saved runs.
	var data := SaveData.default_data()
	check(RunRecords.endless(data).best_wave == 0, "a new profile has no endless record")
	check(RunRecords.record_endless(data, 7, 300.0), "the first run is a best")
	check(not RunRecords.record_endless(data, 5, 900.0) and int(RunRecords.endless(data).best_wave) == 7, "fewer waves is not a best")
	check(RunRecords.record_endless(data, 7, 400.0), "the same waves, standing longer, is a best")
	check(int(RunRecords.endless(data).runs) == 3 and int(RunRecords.endless(data).total_waves) == 19, "runs and waves are counted")
	var saved := {"wave": 4, "boons": ["granary", "nonsense"], "base_hp": 321.0, "units": ["shield", "archer", "healer", "swordsman"], "structures": ["wall", "turret", "generator", "swamp"], "seed": 42, "seconds": 120.0}
	var clean := RunRecords.sanitize_saved(saved)
	check(clean.boons == ["granary"] and int(clean.wave) == 4 and float(clean.base_hp) == 321.0, "a saved run keeps known boons only")
	check(RunRecords.sanitize_saved({"wave": 4, "boons": [], "base_hp": 0.0, "units": saved.units, "structures": saved.structures}).is_empty(), "a saved run with a fallen base is dropped")
	check(RunRecords.sanitize_saved({"wave": 4, "boons": [], "base_hp": 10.0, "units": ["shield"], "structures": saved.structures}).is_empty(), "a saved run needs a valid deck")
	data.runs.endless.saved = saved
	var round_trip := SaveData.sanitize(JSON.parse_string(JSON.stringify(data)))
	check(int(round_trip.runs.endless.best_wave) == 7 and int(round_trip.runs.endless.saved.wave) == 4, "records and the saved run survive a save")
	check(SaveData.sanitize({}).runs.endless.saved.is_empty(), "old profiles get empty records")

	# Screens.
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	main._build_connect_screen()
	await process_frame
	main._build_solo_screen()
	await process_frame
	var menu_button: Button = main.find_child("EndlessButton", true, false)
	check(menu_button != null, "the solo screen offers endless defense")
	menu_button.pressed.emit()
	await process_frame
	var start: Button = main.find_child("EndlessStart", true, false)
	check(start != null and main.find_child("EndlessResume", true, false) == null, "a first run can only start fresh")
	start.pressed.emit()
	await process_frame
	check(EndlessFlow.active(main) and main.local_recorder == null and main.find_child("EndlessSpeedButton", true, false) != null, "the run starts with its own controls and no replay")
	check(main.find_child("PracticeSpeedButton", true, false) == null, "practice tools are not shown")
	var speed: Button = main.find_child("EndlessSpeedButton", true, false)
	speed.pressed.emit()
	check(float(main.endless_run.speed) == 2.0 and speed.text == "2×", "the speed button doubles the pace")
	main.set_process(false)
	var run_director = main.endless_run.director
	var before: float = main.local_model.elapsed
	main._process(0.1)
	check(main.local_model.elapsed - before > 0.15, "at 2x the battle runs twice as fast (%.3f)" % (main.local_model.elapsed - before))
	while run_director.wave == 0:
		main._process(0.1)
	main._process(0.1)
	var mode_label: Label = main.find_child("BattleModeLabel", true, false)
	check(mode_label.text.contains("웨이브 1"), "the clock card names the wave: %s" % mode_label.text)
	check(main.red_hp_label.text.begins_with("남은 적"), "the enemy card counts the wave: %s" % main.red_hp_label.text)
	for i in 30:
		main._process(0.1)
	main.local_model.units = main.local_model.units.filter(func(unit): return int(unit.side) != 1)
	run_director.queue.clear()
	for i in 3:
		main._process(0.1)
	check(main.find_child("EndlessBoonOverlay", true, false) != null, "a beaten wave opens the boon pick")
	var paused_at: float = main.local_model.elapsed
	main._process(0.1)
	check(main.local_model.elapsed == paused_at, "the battle waits during the pick")
	var cards: Array = main.find_children("EndlessBoon_*", "Button", true, false)
	check(cards.size() == 3, "three boon cards")
	cards[0].pressed.emit()
	await process_frame
	check(main.find_child("EndlessBoonOverlay", true, false) == null and run_director.boons.size() == 1, "picking closes the overlay")
	var stored: Dictionary = RunRecords.endless(main.save_data).saved
	check(int(stored.get("wave", 0)) == 2 and stored.boons.size() == 1, "the run is saved at the break: %s" % [stored])
	main._process(0.1) # the time spent picking is discarded
	main._process(0.1)
	check(main.local_model.elapsed > paused_at, "the battle resumes after the pick")
	# Fall: the result records the run.
	main.local_model.base_hp[0] = 0.0
	main.local_model.winner = 1
	main._on_snapshot(main.local_model.snapshot())
	main._show_result(1)
	await process_frame
	var record: Dictionary = RunRecords.endless(main.save_data)
	check(int(record.best_wave) == 1 and int(record.runs) == 1 and record.saved.is_empty(), "the fallen run is recorded and its save cleared: %s" % [record])
	check(main.save_data.stats.ai_matches == 0, "endless runs stay out of the AI record")
	var title_labels: Array = main.result_overlay.find_children("*", "Label", true, false).filter(func(label): return label.text == "웨이브 1 돌파")
	check(not title_labels.is_empty(), "the result names the waves beaten")
	check(main.result_overlay.find_children("*", "Label", true, false).any(func(label): return label.text.begins_with("신기록")), "a first run is a new record")
	# Resume from a saved break.
	RunRecords.endless(main.save_data).saved = RunRecords.sanitize_saved({"wave": 6, "boons": ["granary", "granary"], "base_hp": 250.0, "units": ["paladin", "zombie", "necromancer", "archer"], "structures": ["wall", "swamp", "frost", "seraph"], "seed": 9, "seconds": 300.0})
	main._build_solo_screen()
	await process_frame
	main.find_child("EndlessButton", true, false).pressed.emit()
	await process_frame
	var resume: Button = main.find_child("EndlessResume", true, false)
	check(resume != null and resume.text.contains("웨이브 6"), "a saved run can be resumed")
	resume.pressed.emit()
	await process_frame
	check(EndlessFlow.active(main) and main.local_model.base_hp[0] == 250.0 and main.local_model.unit_decks[0] == ["paladin", "zombie", "necromancer", "archer"], "resuming keeps the base and deck")
	check(is_equal_approx(main.local_model.resource_income(0), BattleModel.RESOURCE_RATE + 2.0), "resuming keeps the boons")
	var resumed = main.endless_run.director
	while resumed.wave < 6:
		main._process(0.1)
	check(resumed.wave == 6 and resumed.waves_cleared() == 5, "the resumed run continues at its wave")
	main._exit_battle_to_menu()
	await process_frame
	check(main.endless_run.is_empty() or not main.local_ai_mode, "leaving ends the mode")
	main._start_local_ai_battle(1)
	await process_frame
	check(main.endless_run.is_empty() and main.find_child("EndlessSpeedButton", true, false) == null, "a practice battle afterwards is a plain practice battle")
	print("endless_mode_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
