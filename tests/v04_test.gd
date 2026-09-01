extends SceneTree

var failures := 0
var checks := 0

func expect_true(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func expect_eq(actual, expected, message: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		printerr("FAIL: %s (actual=%s expected=%s)" % [message, actual, expected])

func _init() -> void:
	var BattleModel = load("res://scripts/BattleModel.gd")
	var model = BattleModel.new()
	expect_eq(BattleModel.STRUCTURE_STATS.wall.hp, 230.0, "v0.4 wall hp")
	expect_true(not BattleModel.STRUCTURE_STATS.has("jump_pad"), "jump pad is removed")
	expect_eq(BattleModel.STRUCTURE_STATS.swamp.radius, 95.0, "swamp displays its actual radius")
	expect_true(BattleModel.STRUCTURE_STATS.has("turret"), "turret exists")
	expect_true(BattleModel.STRUCTURE_STATS.has("generator"), "generator exists")
	expect_eq(BattleModel.STRUCTURE_STATS.turret.range, 240.0, "turret range is useful but remains shorter than archer range")
	expect_true(model.configure_deck(0, ["shield", "archer", "healer"], ["wall", "turret", "generator"]), "valid 3+3 deck accepted")
	expect_true(not model.configure_deck(0, ["shield", "shield", "healer"], ["wall", "turret", "generator"]), "duplicate deck rejected")
	model.resources[0] = 150.0
	expect_true(not model.spawn_unit(0, "swordsman"), "unit outside deck rejected")
	expect_true(model.spawn_unit(0, "archer"), "unit inside deck accepted")
	expect_true(model.place_structure(0, "wall", 500.0), "wall in deck accepted")
	expect_true(not model.place_structure(0, "turret", 540.0), "minimum placement spacing enforced")
	expect_eq(model.structure_placement_error(0, "turret", 540.0), "구조물이 너무 가깝습니다.", "spacing reason is actionable")
	expect_true(not model.place_structure(0, "generator", 500.0), "generator cannot be placed at front")
	expect_eq(model.structure_placement_error(0, "generator", 500.0), "발전기는 후방에만 설치할 수 있습니다.", "rear-zone reason")
	var economy = BattleModel.new()
	economy.resources[0] = 100.0
	economy.configure_deck(0, ["shield", "archer", "healer"], ["generator", "wall", "swamp"])
	expect_true(economy.place_structure(0, "generator", 250.0), "generator can be placed in rear zone")
	var before: float = economy.resources[0]
	economy.tick(1.0)
	expect_eq(economy.resources[0], before + 9.0, "generator adds one resource per second")
	var shielding = BattleModel.new()
	shielding.resources = [150.0, 150.0]
	shielding.configure_deck(1, ["shield", "swordsman", "archer"], ["wall", "turret", "generator"])
	shielding.spawn_unit(0, "archer")
	shielding.spawn_unit(1, "swordsman")
	shielding.place_structure(1, "wall", 700.0)
	shielding.units[0].x = 560.0
	shielding.units[1].x = 760.0
	var protected_hp: float = shielding.units[1].hp
	var wall_hp: float = shielding.structures[0].hp
	shielding.tick(2.0)
	expect_eq(shielding.units[1].hp, protected_hp, "wall shields units behind it")
	expect_true(shielding.structures[0].hp < wall_hp, "attacker hits blocking wall")
	var turret = BattleModel.new()
	turret.resources = [150.0, 150.0]
	turret.configure_deck(0, ["shield", "archer", "healer"], ["turret", "wall", "swamp"])
	turret.place_structure(0, "turret", 500.0)
	turret.spawn_unit(1, "swordsman")
	turret.units[0].x = 620.0
	var target_hp: float = turret.units[0].hp
	turret.tick(1.6)
	expect_true(turret.units[0].hp < target_hp, "turret attacks enemy units")
	expect_true(not turret.drain_combat_events().is_empty(), "combat events are separate from snapshot")
	expect_eq(turret.snapshot().keys().size(), 6, "snapshot exact key set remains stable")
	var turret_shielding = BattleModel.new()
	turret_shielding.resources = [150.0, 150.0]
	turret_shielding.configure_deck(0, ["shield", "archer", "healer"], ["turret", "wall", "swamp"])
	turret_shielding.configure_deck(1, ["swordsman", "shield", "archer"], ["wall", "swamp", "generator"])
	turret_shielding.place_structure(0, "turret", 550.0)
	turret_shielding.place_structure(1, "wall", 670.0)
	turret_shielding.spawn_unit(1, "swordsman")
	turret_shielding.units[0].x = 700.0
	var turret_blocked_unit_hp: float = turret_shielding.units[0].hp
	var turret_blocking_wall_hp: float = turret_shielding.structures[1].hp
	turret_shielding.tick(1.6)
	expect_eq(turret_shielding.units[0].hp, turret_blocked_unit_hp, "turret cannot shoot a unit behind an enemy wall")
	expect_true(turret_shielding.structures[1].hp < turret_blocking_wall_hp, "turret attacks the blocking wall first")
	var boundary_spacing = BattleModel.new()
	boundary_spacing.resources = [150.0, 150.0]
	expect_true(boundary_spacing.place_structure(0, "wall", 610.0), "blue can build at its forward boundary")
	expect_true(boundary_spacing.place_structure(1, "wall", 670.0), "enemy structures do not block red boundary placement")
	var BattleView = load("res://scripts/BattleView.gd")
	var placement_view = BattleView.new()
	placement_view.own_side = 0
	placement_view.snapshot = {"resources": [10.0, 150.0], "structures": [{"id": 1, "side": 1, "kind": "wall", "x": 670.0, "hp": 230.0, "max_hp": 230.0}]}
	expect_eq(placement_view.placement_error("turret", 500.0), "자원이 부족합니다.", "online preview rejects unaffordable structures")
	placement_view.snapshot.resources[0] = 150.0
	expect_eq(placement_view.placement_error("wall", 610.0), "", "enemy structures do not block the local placement preview")
	var released_positions: Array = []
	placement_view.battlefield_clicked.connect(func(x): released_positions.append(x))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(500.0, 100.0)
	placement_view._gui_input(press)
	expect_true(released_positions.is_empty(), "building placement does not fire on pointer press")
	press.pressed = false
	placement_view._gui_input(press)
	expect_eq(released_positions.size(), 1, "building placement fires on pointer release")
	placement_view.free()

	var SaveData = load("res://scripts/SaveData.gd")
	expect_true(SaveData != null, "versioned user save module loads")
	if SaveData != null:
		var defaults: Dictionary = SaveData.default_data()
		expect_true(bool(defaults.settings.fullscreen), "new installs start in fullscreen mode")
		expect_eq(defaults.save_version, 1, "save schema begins at version 1")
		expect_eq(defaults.deck_presets.size(), 3, "three deck presets exist")
		expect_eq(defaults.campaign_records.size(), 10, "ten campaign records exist")
		var repaired: Dictionary = SaveData.sanitize({"save_version": 1, "last_deck": 99, "settings": "broken"})
		expect_eq(repaired.last_deck, 0, "invalid values recover to defaults")
		expect_true(repaired.settings is Dictionary, "invalid settings recover independently")
		expect_eq(SaveData.campaign_stars(1, true, 60.0, 450.0), 3, "stage-specific star targets work")
		expect_eq(SaveData.campaign_stars(1, true, 60.0, 1.0), 1, "fast wins without the HP target do not skip to three stars")
		expect_eq(SaveData.campaign_stars(1, true, 120.0, 450.0), 2, "HP target alone awards two stars")
		var unsafe_settings := defaults.duplicate(true)
		unsafe_settings.settings.master_volume = 999.0
		unsafe_settings.settings.bgm_volume = -5.0
		unsafe_settings.settings.effect_intensity = -500.0
		unsafe_settings.settings.window_size = "99999x1"
		unsafe_settings.settings.fps_limit = 999
		var safe_settings: Dictionary = SaveData.sanitize(unsafe_settings).settings
		expect_eq(safe_settings.master_volume, 1.0, "master volume is clamped")
		expect_eq(safe_settings.bgm_volume, 0.0, "BGM volume is clamped")
		expect_eq(safe_settings.effect_intensity, 0.2, "effect intensity is clamped")
		expect_eq(safe_settings.window_size, "1280x720", "unknown window sizes recover to default")
		expect_eq(safe_settings.fps_limit, 60, "unknown FPS limits recover to default")
	var ServerAI = load("res://scripts/ServerAI.gd")
	expect_true(not ServerAI.stage_summary(3).contains("해금"), "AI stage copy does not claim nonexistent unlocks")
	expect_true(ServerAI.stage_summary(3).contains("방어"), "AI stage copy describes its actual defensive behavior")
	var endless = BattleModel.new()
	endless.tick(301.0)
	expect_eq(endless.winner, -1, "battle no longer ends at a fixed time limit")

	var NetworkController = load("res://scripts/NetworkController.gd")
	expect_true(NetworkController.validate_deck_payload(["shield", "archer", "healer"], ["wall", "turret", "generator"]), "server accepts a valid deck payload")
	expect_true(not NetworkController.validate_deck_payload(["shield", "archer", "intruder"], ["wall", "turret", "generator"]), "server rejects unknown deck entries")
	expect_true(not NetworkController.validate_deck_payload(["shield", "archer"], ["wall", "turret", "generator"]), "server rejects wrong deck counts")
	var network = NetworkController.new()
	expect_true(network.has_signal("structure_placement_result"), "server placement results have a client signal")
	expect_true(network.set_client_deck(["shield", "archer", "healer"], ["wall", "turret", "generator"]), "client can select a valid deck before connecting")
	expect_true(not network.set_client_deck(["shield"], ["wall", "turret", "generator"]), "client cannot select an invalid deck")
	network.free()

	if failures == 0:
		print("PASS: %d v0.4 checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d v0.4 checks" % [failures, checks])
		quit(1)
