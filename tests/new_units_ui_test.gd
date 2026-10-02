extends SceneTree

var checks := 0
var failures := 0
var capture_dir := ""
var main
const Save = preload("res://scripts/SaveData.gd")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func text_of(node: Node) -> String:
	var result := ""
	if node is Label or node is Button: result += node.text + "\n"
	for child in node.get_children(): result += text_of(child)
	return result

func capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))

func click(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.pressed.emit()
		return
	var point := button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		get_root().push_input(event, true)
		await process_frame

func _initialize() -> void:
	get_root().size = Vector2i(1280,720)
	Engine.max_fps = 30
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	call_deferred("run")

func run() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("New-unit UI test watchdog expired"); quit(1))
	var Main = load("res://scripts/Main.gd")
	check(Main != null, "Main loads with all new textures")
	if Main == null: quit(1); return
	var bootstrap := Control.new(); bootstrap.name = "Bootstrap"; get_root().add_child(bootstrap)
	main = load("res://scenes/Main.tscn").instantiate(); main.name="Main"; bootstrap.add_child(main)
	await process_frame
	main.set_process(false)
	main.save_data = Save.default_data()
	main.save_data.tutorial_completed = true
	main.save_data.deck_presets[0].units = ["berserker","warlock","necromancer"]
	main.save_data.settings.battle_effects = true
	main.save_data.settings.damage_numbers = true
	main.save_data.settings.screen_shake = false
	main._build_deck_screen(0)
	await process_frame
	var grid = main.find_child("DeckUnitGrid",true,false)
	check(grid != null and grid.get_child_count() == 7, "seven purchasable units are available")
	check(main.find_child("DeckUnit_skeleton",true,false) == null, "skeleton has no deck-selection card")
	for kind in ["berserker","warlock","necromancer"]:
		var card = main.find_child("DeckUnit_"+kind,true,false)
		check(card != null and card.button_pressed and not card.tooltip_text.is_empty(), "new selected deck card and trait tooltip: "+kind)
	check(main.find_child("DeckSaveButton",true,false).get_global_rect().end.y <= 720.0, "fixed deck save action stays inside the viewport")
	await capture("new-deck")
	main.campaign_mode = false
	main._start_local_ai_battle(1)
	main.set_process(false)
	await process_frame
	for kind in ["berserker","warlock","necromancer"]:
		main.local_model.resources[0] = 180.0
		main._on_snapshot(main.local_model.snapshot())
		var buttons: Array = main.purchase_buttons.filter(func(button): return button.get_meta("unit_kind", "") == kind)
		check(buttons.size() == 1 and not buttons[0].disabled, "purchase card is present and affordable: "+kind)
		if buttons.is_empty(): continue
		var before: int = main.local_model.units.size()
		await click(buttons[0])
		check(main.local_model.units.size() == before + 1 and main.local_model.units.back().kind == kind, "actual portrait click spawns: "+kind)
		check(buttons[0].tooltip_text == BattleModel.unit_stat_summary(kind), "battle tooltip reflects requested base stats: "+kind)
	for unit in main.local_model.units: unit.speed=0.0
	main.local_model.units[0].x = 350.0
	main.local_model.units[0].hp = main.local_model.units[0].max_hp * 0.5
	main.local_model.units[1].x = 490.0; main.local_model.units[1].cooldown=0.0
	main.local_model.units[2].x = 650.0; main.local_model.units[2].cooldown=0.0
	main.local_model.resources[1] = 180.0
	main.local_model.spawn_unit(1,"shield")
	var enemy: Dictionary = main.local_model.units.back()
	enemy.x=740.0; enemy.speed=0.0; enemy.cooldown=999.0
	main.local_model.tick(5.0)
	main._on_snapshot(main.local_model.snapshot())
	main._on_combat_events(main.local_model.drain_combat_events())
	check(main.local_model.units.any(func(unit): return unit.kind == "skeleton"), "summoned skeleton reaches the displayed snapshot")
	check(main.battle_view.cursed_units.has(enemy.id), "curse debuff is visibly tracked on the actual victim")
	for kind in ["berserker","warlock","necromancer","skeleton"]:
		var texture: Texture2D = BattleView.UNIT_TEXTURES[kind]
		var image := texture.get_image()
		if image.is_compressed(): image.decompress()
		check(image.get_pixel(0,0).a == 0.0 and image.get_pixel(image.get_width()-1,image.get_height()-1).a == 0.0, "portrait matte is transparent: "+kind)
		check(BattleView.UNIT_WALK_TEXTURES[kind].size() == 6 and BattleView.UNIT_ATTACK_TEXTURES[kind].size() == 3, "walk and attack animations exist: "+kind)
	await process_frame
	await capture("new-units-battle")
	main._show_stats_panel()
	await process_frame
	var scroll = main.find_child("UnitStatsScroll",true,false)
	check(scroll != null and scroll.get_v_scroll_bar().max_value > scroll.size.y, "expanded stats panel scrolls")
	check(text_of(main.stats_overlay).contains("해골") and text_of(main.stats_overlay).contains("네크로맨서"), "all new unit and summon stats are included in Korean")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await process_frame
	await capture("new-unit-stats")
	main._dismiss_stats_panel()
	bootstrap.queue_free()
	await process_frame
	if failures == 0: print("PASS: %d new-unit UI and asset checks" % checks)
	quit(0 if failures == 0 else 1)
