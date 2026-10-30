extends SceneTree
## A tank in the same spot as the enemy a unit would hit takes the hit first, with and without the lane index;
## the swamp has no health, so nothing attacks it and it lasts until its lifetime ends.
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func unit(id: int, side: int, kind: String, x: float) -> Dictionary:
	var stats: Dictionary = BattleModel.UNIT_STATS[kind]
	return {"id": id, "side": side, "kind": kind, "hp": 500.0, "max_hp": 500.0, "damage": 0.0, "interval": 99.0, "speed": 0.0, "range": float(stats.range), "x": x, "cooldown": 99.0}

func target_of(model: BattleModel, attacker: Dictionary, indexed: bool):
	BattleModel.targeting_index = indexed
	model._index_lanes()
	var found = model._find_target(attacker)
	model._indexed = false
	BattleModel.targeting_index = true
	return found

func _initialize() -> void:
	for indexed in [false, true]:
		var model := BattleModel.new()
		var attacker := unit(1, 0, "swordsman", 1000.0)
		var front := unit(2, 1, "archer", 1030.0)
		var tank := unit(3, 1, "shield", 1040.0)
		model.units = [attacker, front, tank]
		check(target_of(model, attacker, indexed) == tank, "a tank in the same spot is hit first (indexed %s)" % indexed)
		tank.x = 1080.0
		check(target_of(model, attacker, indexed) == front, "a tank further back does not draw the hit (indexed %s)" % indexed)
		tank.x = 1030.0
		var second := unit(4, 1, "shield", 1025.0)
		model.units.append(second)
		check(target_of(model, attacker, indexed) == second, "of two tanks the nearer is hit (indexed %s)" % indexed)

	var swamp_field := BattleModel.new()
	swamp_field.configure_deck(1, ["shield", "archer", "healer", "swordsman"], ["wall", "swamp", "turret", "generator"])
	swamp_field.resources[1] = 999.0
	var placed := swamp_field.place_structure(1, "swamp", BattleModel.RED_BUILD_MIN + 40.0)
	check(placed and not BattleModel.has_health("swamp") and BattleModel.has_health("wall"), "the swamp has no health, walls do")
	var swamp: Dictionary = swamp_field.structures.back()
	var walker := unit(10, 0, "swordsman", float(swamp.x) - 20.0)
	walker.damage = 999.0
	walker.cooldown = 0.0
	walker.interval = 0.1
	swamp_field.units = [walker]
	for i in 30 * 2:
		swamp_field.tick(1.0 / 30.0)
	check(swamp_field.structures.has(swamp) and float(swamp.hp) > 0.0, "units cannot attack a swamp")
	for i in 30 * int(BattleModel.STRUCTURE_STATS.swamp.lifetime):
		swamp_field.tick(1.0 / 30.0)
	check(not swamp_field.structures.has(swamp), "the swamp ends with its lifetime")
	print("guard and swamp test: %d failures" % failures)
	quit(1 if failures > 0 else 0)
