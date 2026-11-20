extends SceneTree
## Batch-2 units (hero, raider, preacher, psychic, shaman) follow their rules in the battle engine.

var checks := 0
var failures := 0
const DT := 1.0 / 30.0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func model(a: Array, b: Array) -> BattleModel:
	var result := BattleModel.new()
	result.configure_deck(0, a, ["wall", "swamp", "turret", "frost"])
	result.configure_deck(1, b, ["wall", "swamp", "turret", "frost"])
	result.resources = [100.0, 100.0]
	return result

func by_kind(battle: BattleModel, kind: String, side: int = -1) -> Array:
	return battle.units.filter(func(unit): return String(unit.kind) == kind and (side < 0 or int(unit.side) == side))

func buy(battle: BattleModel, side: int, kind: String) -> Dictionary:
	battle.resources[side] = 180.0
	battle.spawn_cooldowns[side].clear()
	battle.spawn_unit(side, kind)
	return by_kind(battle, kind, side).back()

func _initialize() -> void:
	for kind in ["hero", "raider", "preacher", "psychic", "shaman"]:
		check(BattleModel.UNIT_STATS.has(kind) and not BattleModel.unit_stat_summary(kind).is_empty() and not BattleModel.unit_role(kind).is_empty(), "unit data and card text: " + kind)

	# Hero: allies in its aura recover attacks 20 percent faster (the hero too).
	var aura := model(["hero", "swordsman", "archer", "shield"], ["shield", "swordsman", "archer", "healer"])
	var hero := buy(aura, 0, "hero")
	var near := buy(aura, 0, "swordsman")
	var far := buy(aura, 0, "swordsman")
	hero.x = 300.0; near.x = 350.0; far.x = 600.0
	for unit in [hero, near, far]: unit.speed = 0.0
	near.cooldown = 1.0; far.cooldown = 1.0
	aura.tick(0.1)
	check(is_equal_approx(float(by_kind(aura, "swordsman", 0)[0].cooldown), 1.0 - 0.1 * 1.2), "a swordsman in the aura recovers 20 percent faster")
	check(is_equal_approx(float(by_kind(aura, "swordsman", 0)[1].cooldown), 1.0 - 0.1), "one outside it does not")
	check(not aura.spawn_unit(0, "hero"), "one hero at a time")

	# Raider: a kill takes 25 percent of the victim's cost (up to 15) from the enemy's resources.
	var loot := model(["raider", "shield", "archer", "healer"], ["shield", "swordsman", "archer", "healer"])
	var raider := buy(loot, 0, "raider")
	var victim := buy(loot, 1, "swordsman")
	raider.x = 500.0; victim.x = 530.0; victim.speed = 0.0; raider.speed = 0.0
	victim.hp = 3.0; victim.cooldown = 99.0; raider.cooldown = 0.0
	loot.resources = [50.0, 100.0]
	loot.tick(DT)
	check(is_equal_approx(float(loot.resources[1]), 100.0 + 8.0 * DT - 7.5), "the enemy loses a quarter of a swordsman's cost")
	check(is_equal_approx(float(loot.resources[0]), 50.0 + 8.0 * DT + 7.5), "the raider's side gains it")
	check(by_kind(loot, "raider")[0].has("plunder_remaining"), "plunder then waits its cooldown")

	# Preacher: a kill hands over the victim's ability (rage from a berserker).
	var faith := model(["preacher", "shield", "archer", "healer"], ["berserker", "swordsman", "archer", "healer"])
	var preacher := buy(faith, 0, "preacher")
	var berserker := buy(faith, 1, "berserker")
	preacher.x = 500.0; berserker.x = 530.0; preacher.speed = 0.0; berserker.speed = 0.0
	berserker.hp = 2.0; berserker.cooldown = 99.0; preacher.cooldown = 0.0
	faith.tick(DT)
	preacher = by_kind(faith, "preacher")[0]
	check(String(preacher.get("gift", "")) == "berserker", "the preacher takes a berserker's rage")
	preacher.hp = float(preacher.max_hp) * 0.4
	check(BattleModel.is_enraged(preacher), "and rages below half health")

	# Psychic: arrives in front of the enemy's foremost structure, stalled for a moment.
	var leap := model(["psychic", "shield", "archer", "healer"], ["shield", "swordsman", "archer", "healer"])
	leap.resources[1] = 180.0
	check(leap.place_structure(1, "turret", BattleModel.RED_BUILD_MIN + 40.0), "enemy turret placed")
	var turret_x := float(leap.structures.back().x)
	var psychic := buy(leap, 0, "psychic")
	check(is_equal_approx(float(psychic.x), turret_x - 30.0), "the psychic appears in front of the enemy turret")
	check(psychic.has("stall_remaining"), "and cannot act at once")
	check(float(leap.spawn_cooldowns[0].psychic) == 20.0, "its card waits 20 s")

	# Shaman: an enemy falling near it rises on the shaman's side at half health.
	var hex := model(["shaman", "swordsman", "archer", "healer"], ["shield", "swordsman", "archer", "healer"])
	var shaman := buy(hex, 0, "shaman")
	var blade := buy(hex, 0, "swordsman")
	var foe := buy(hex, 1, "swordsman")
	shaman.x = 400.0; blade.x = 480.0; foe.x = 510.0
	for unit in [shaman, blade, foe]: unit.speed = 0.0
	foe.hp = 2.0; foe.cooldown = 99.0; blade.cooldown = 0.0; shaman.cooldown = 99.0
	hex.tick(DT)
	var raised := by_kind(hex, "swordsman", 0).filter(func(unit): return bool(unit.get("converted", false)))
	check(raised.size() == 1, "the fallen swordsman rises for the shaman")
	check(raised.size() == 1 and is_equal_approx(float(raised[0].max_hp), float(BattleModel.UNIT_STATS.swordsman.hp) * 0.5), "at half health")
	check(by_kind(hex, "shaman")[0].has("convert_remaining"), "conversion then waits its cooldown")

	print("PASS: %d batch-2 unit checks" % checks if failures == 0 else "FAILED: %d of %d" % [failures, checks])
	quit(0 if failures == 0 else 1)
