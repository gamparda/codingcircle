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
	expect_true(BattleModel != null, "BattleModel script loads")
	if BattleModel == null:
		finish()
		return

	var model = BattleModel.new()
	model.resources[0] = 0.0
	expect_eq(model.spawn_unit(0, "swordsman"), false, "cannot spawn without resources")
	model.resources[0] = 100.0
	expect_eq(model.spawn_unit(0, "swordsman"), true, "spawns with enough resources")
	expect_eq(int(model.resources[0]), 75, "cost is deducted once")
	expect_eq(model.units.size(), 1, "exactly one unit is created")

	var income_before: float = model.resources[0]
	model.tick(1.0)
	expect_true(model.resources[0] > income_before, "resources regenerate")

	var duel = BattleModel.new()
	duel.resources = [100.0, 100.0]
	duel.spawn_unit(0, "swordsman")
	duel.spawn_unit(1, "swordsman")
	duel.units[0].x = 620.0
	duel.units[1].x = 650.0
	var hp_before: float = duel.units[1].hp
	duel.tick(1.0)
	expect_true(duel.units[1].hp < hp_before, "units attack enemies in range")

	var structures = BattleModel.new()
	structures.resources[0] = 200.0
	expect_true(structures.place_structure(0, "wall", 500.0), "wall can be placed in own zone")
	expect_true(not structures.place_structure(0, "wall", 900.0), "wall cannot be placed in enemy zone")
	expect_true(structures.place_structure(0, "swamp", 520.0), "swamp can be placed")
	expect_true(structures.place_structure(0, "jump_pad", 540.0), "jump pad can be placed")
	expect_true(not structures.place_structure(0, "wall", 560.0), "structure limit is enforced")

	var base_rush = BattleModel.new()
	base_rush.resources[0] = 100.0
	base_rush.spawn_unit(0, "swordsman")
	base_rush.units[0].x = 1170.0
	base_rush.units[0].damage = 999.0
	base_rush.tick(1.0)
	expect_eq(base_rush.winner, 0, "destroying the enemy base ends the match")

	var healing = BattleModel.new()
	healing.resources[0] = 150.0
	healing.spawn_unit(0, "shield")
	var healer_spawned: bool = healing.spawn_unit(0, "healer")
	expect_true(healer_spawned, "healer can be produced")
	if healer_spawned:
		healing.units[0].x = 400.0
		healing.units[1].x = 360.0
		healing.units[0].hp -= 50.0
		var wounded_hp: float = healing.units[0].hp
		healing.tick(1.3)
		expect_true(healing.units[0].hp > wounded_hp, "healer restores a wounded ally in range")
		expect_true(healing.units[0].hp <= healing.units[0].max_hp, "healing never exceeds maximum health")

	var MatchRegistry = load("res://scripts/MatchRegistry.gd")
	expect_true(MatchRegistry != null, "MatchRegistry script loads")
	if MatchRegistry != null:
		var registry = MatchRegistry.new()
		expect_eq(registry.add_player(11), {}, "first player waits")
		var paired: Dictionary = registry.add_player(22)
		expect_eq(paired.get(11), 0, "first player is assigned side 0")
		expect_eq(paired.get(22), 1, "second player is assigned side 1")
		expect_true(registry.has_match(11) and registry.has_match(22), "both peers belong to a server match")
		registry.remove_player(11)
		expect_true(not registry.has_match(11) and not registry.has_match(22), "disconnect removes the whole match")

	var ServerAI = load("res://scripts/ServerAI.gd")
	expect_true(ServerAI != null, "ServerAI script loads")
	if ServerAI != null:
		var ai_model = BattleModel.new()
		ai_model.resources[1] = 150.0
		var ai = ServerAI.new(1)
		ai.update(ai_model, 1.0)
		expect_true(ai_model.units.any(func(unit): return unit.side == 1), "AI spends server-owned resources to spawn a unit")
		ai.update(ai_model, 6.0)
		expect_true(ai_model.structures.any(func(structure): return structure.side == 1), "AI places a structure through normal game rules")

	var UpdateManager = load("res://scripts/UpdateManager.gd")
	expect_true(UpdateManager != null, "UpdateManager script loads")
	if UpdateManager != null:
		expect_true(UpdateManager.is_newer_version("0.3.2", "0.3.1"), "newer patch version is detected")
		expect_true(UpdateManager.is_newer_version("0.4.0", "0.3.99"), "newer minor version is detected")
		expect_true(not UpdateManager.is_newer_version("0.3.1", "0.3.1"), "same version is not an update")
		expect_true(not UpdateManager.is_newer_version("0.2.9", "0.3.0"), "older version is rejected")

	var Main = load("res://scripts/Main.gd")
	expect_true(Main != null, "Main script loads")
	if Main != null:
		expect_eq(Main.OFFICIAL_SERVER_ADDRESS, "ruellyya.kr", "official server address is fixed")
		expect_eq(Main.OFFICIAL_SERVER_PORT, 7777, "official server port is fixed")

	finish()

func finish() -> void:
	if failures == 0:
		print("PASS: %d checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d checks" % [failures, checks])
		quit(1)
