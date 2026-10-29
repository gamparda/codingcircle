extends SceneTree
# Knockback: the first time a unit falls to half health it is thrown back once, toward its own base.
const Network = preload("res://scripts/NetworkController.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func unit_at(model: BattleModel, side: int, kind: String, x: float) -> Dictionary:
	model.spawn_cooldowns[side].clear()
	model.resources[side] = 999.0
	model.spawn_unit(side, kind)
	var unit: Dictionary = model.units.back()
	unit.x = x
	return unit

func _initialize() -> void:
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer", "zombie"], BattleModel.DEFAULT_STRUCTURE_DECK)
	model.configure_deck(1, ["shield", "swordsman", "archer", "zombie"], BattleModel.DEFAULT_STRUCTURE_DECK)
	var red := unit_at(model, 1, "swordsman", 800.0)
	var blue := unit_at(model, 0, "swordsman", 760.0)
	var hit := float(red.max_hp) * 0.3
	model._damage_target(blue, red, hit)
	check(is_equal_approx(float(red.x), 800.0), "a light hit does not throw the unit back")
	model._damage_target(blue, red, hit)
	check(is_equal_approx(float(red.x), 800.0 + BattleModel.KNOCKBACK_DISTANCE), "falling to half health throws a red unit back toward the red base")
	check(model.combat_events.any(func(event): return event.type == "KNOCKBACK" and event.target_id == red.id), "the knockback is announced for the view")
	model._damage_target(blue, red, 1.0)
	check(is_equal_approx(float(red.x), 800.0 + BattleModel.KNOCKBACK_DISTANCE), "a unit is thrown back only once")
	model._damage_target(red, blue, float(blue.max_hp) * 0.6)
	check(is_equal_approx(float(blue.x), 760.0 - BattleModel.KNOCKBACK_DISTANCE), "a blue unit is thrown back toward the blue base")
	var edge := unit_at(model, 0, "shield", BattleModel.FIELD_LEFT + 20.0)
	model._damage_target(red, edge, float(edge.max_hp) * 0.6)
	check(is_equal_approx(float(edge.x), BattleModel.FIELD_LEFT), "a knockback never leaves the field")
	var dead := unit_at(model, 1, "archer", 900.0)
	model._damage_target(blue, dead, 9999.0)
	check(is_equal_approx(float(dead.x), 900.0), "a unit killed outright is not thrown")
	model.tick(1.0 / 30.0)
	check(Network.is_valid_snapshot(model.snapshot()), "the online snapshot schema is unchanged")
	# A revived zombie does not get a second knockback.
	var zombie := unit_at(model, 0, "zombie", 600.0)
	model._damage_target(red, zombie, float(zombie.max_hp) * 0.6)
	var after_first := float(zombie.x)
	model._damage_target(red, zombie, 9999.0)
	for i in 90: model.tick(1.0 / 30.0)
	var revived: Array = model.units.filter(func(unit): return unit.id == zombie.id and float(unit.hp) > 0.0)
	if not revived.is_empty():
		var x := float(revived[0].x)
		model._damage_target(red, revived[0], float(revived[0].hp) * 0.5)
		check(is_equal_approx(float(revived[0].x), x), "a revived zombie is not thrown a second time")
	check(after_first < 600.0, "the zombie was thrown on its first life")
	print("knockback_test failures=%d" % failures)
	quit(1 if failures else 0)
