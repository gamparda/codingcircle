extends SceneTree
# Spells in the tactic slot: where they can be cast, cooldowns and uses, each effect, resurrection
# bookkeeping, the online snapshot schema, determinism and the AI's targets.
const Network = preload("res://scripts/NetworkController.gd")

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func model_with(spells: Array) -> BattleModel:
	var model := BattleModel.new()
	model.configure_deck(0, ["swordsman", "shield", "archer"], spells)
	model.configure_deck(1, ["swordsman", "shield", "archer"], ["wall", "swamp", "turret"])
	model.resources = [180.0, 180.0]
	return model

func put(model: BattleModel, side: int, kind: String, x: float) -> Dictionary:
	model.spawn_cooldowns[side].clear()
	model.resources[side] = 180.0
	model.spawn_unit(side, kind)
	var unit: Dictionary = model.units.back()
	unit.x = x
	return unit

func run_for(model: BattleModel, seconds: float) -> void:
	var steps := int(round(seconds / (1.0 / 30.0)))
	for step in steps:
		model.tick(1.0 / 30.0)

func _initialize() -> void:
	check(BattleModel.is_spell("lightning") and not BattleModel.is_spell("wall"), "spells are tactic cards marked in data")
	check(Network.validate_deck_payload(["swordsman", "shield", "archer", "healer"], ["wall", "lightning", "seraph", "generator"]), "a deck may mix structures and spells")

	# Lightning: anywhere on the field, strongest enemy in the radius, then a cooldown.
	var model := model_with(["lightning", "fireball", "frost"])
	var tank := put(model, 1, "shield", 900.0)
	var sword := put(model, 1, "swordsman", 930.0)
	tank.speed = 0.0; sword.speed = 0.0
	check(model.structure_placement_error(0, "lightning", 900.0).is_empty(), "spells can be cast in the enemy half")
	check(not model.structure_placement_error(0, "wall", 900.0).is_empty(), "structures still need the own build zone")
	var before := float(model.resources[0])
	check(model.place_structure(0, "lightning", 910.0) and model.structures.is_empty(), "casting creates no structure")
	check(is_equal_approx(float(model.resources[0]), before - 50.0), "casting costs resources")
	check(model.structure_placement_error(0, "lightning", 910.0).contains("다시 쓸 수"), "a spell waits for its cooldown")
	var tank_hp := float(tank.hp)
	run_for(model, 0.7)
	check(float(tank.hp) <= tank_hp - 120.0 + 0.01 and float(sword.hp) == float(sword.max_hp), "lightning hits only the strongest enemy in reach")
	run_for(model, 12.0)
	check(model.structure_placement_error(0, "lightning", 910.0).is_empty(), "the cooldown runs out")

	# Fireball: thrown from the base, lands later the farther it goes, hits everyone in the radius.
	model = model_with(["lightning", "fireball", "frost"])
	var first := put(model, 1, "swordsman", 800.0)
	var second := put(model, 1, "archer", 840.0)
	var outside := put(model, 1, "swordsman", 1000.0)
	for unit in [first, second, outside]: unit.speed = 0.0
	model.place_structure(0, "fireball", 820.0)
	var cast: Dictionary = model.spell_casts[0]
	check(float(cast.lands_at) > 0.25 + 0.5, "a far fireball takes time to arrive")
	run_for(model, float(cast.lands_at) + 0.05)
	check(float(first.hp) < float(first.max_hp) and float(second.hp) < float(second.max_hp) and float(outside.hp) == float(outside.max_hp), "the fireball hits only inside its radius")

	# Frost: frozen enemies neither move nor attack.
	model = model_with(["lightning", "fireball", "frost"])
	var walker := put(model, 1, "swordsman", 700.0)
	model.place_structure(0, "frost", 700.0)
	run_for(model, 0.45)
	var frozen_x := float(walker.x)
	check(walker.has("frozen_remaining"), "frost freezes enemies in the radius")
	run_for(model, 1.0)
	check(is_equal_approx(float(walker.x), frozen_x), "frozen units do not move")
	run_for(model, 1.0)
	check(not walker.has("frozen_remaining") and float(walker.x) < frozen_x, "units move again after the freeze")

	# Blessing: allies attack faster while it lasts.
	model = model_with(["blessing", "fireball", "frost"])
	var ally := put(model, 0, "swordsman", 400.0)
	var plain := float(model.support_attack_speed(ally))
	model.place_structure(0, "blessing", 400.0)
	run_for(model, 0.05)
	check(ally.has("blessed_remaining") and is_equal_approx(model.support_attack_speed(ally), plain * 1.3), "blessing speeds allied attacks by 30%")

	# Resurrection: own half only, bought units only, newest first, at 40%, twice a battle.
	model = model_with(["seraph", "fireball", "frost"])
	check(not model.structure_placement_error(0, "seraph", 900.0).is_empty(), "the seraph descends only on the caster's side")
	for index in 6:
		var doomed := put(model, 0, "swordsman" if index % 2 == 0 else "archer", 300.0)
		doomed.hp = 0.0
	run_for(model, 0.05)
	check(model.fallen[0].size() == 6, "fallen bought units are remembered")
	var count_before := model.units.size()
	check(model.place_structure(0, "seraph", 400.0), "the seraph is cast in the own zone")
	run_for(model, 1.05)
	var raised: Array = model.units.filter(func(unit): return unit.get("revived", false))
	check(raised.size() == 5 and model.units.size() == count_before + 5, "five fallen allies return")
	check(raised.all(func(unit): return is_equal_approx(float(unit.max_hp), float(BattleModel.UNIT_STATS[unit.kind].hp) * 0.4)), "they return at 40% health")
	check(model.fallen[0].size() == 1, "the oldest fallen stay down")
	for unit in raised: unit.hp = 0.0
	run_for(model, 0.05)
	check(model.fallen[0].size() == 1, "raised units are not raised again")
	model.spell_cooldowns[0].clear()
	model.resources[0] = 180.0
	check(model.place_structure(0, "seraph", 400.0), "the seraph descends a second time")
	model.spell_cooldowns[0].clear()
	check(model.structure_placement_error(0, "seraph", 400.0).contains("번만"), "the seraph descends twice a battle")

	# Online schema and determinism.
	model = model_with(["lightning", "fireball", "frost"])
	put(model, 1, "shield", 900.0)
	model.place_structure(0, "fireball", 900.0)
	model.place_structure(0, "frost", 880.0)
	run_for(model, 0.45)
	check(Network.is_valid_snapshot(model.snapshot()), "snapshots with spells in flight and frozen units pass the online schema")
	var banned := model_with(["wall", "lightning", "fireball", "frost"])
	banned.banned[0] = ["lightning"]
	banned.banned[1] = ["shield"]
	check(not banned.spawn_unit(1, "shield") and banned.spawn_unit(1, "archer"), "a ranked ban blocks only the banned unit")
	check(not banned.structure_placement_error(0, "lightning", 900.0).is_empty(), "a ranked ban blocks the banned spell")
	var banned_snapshot := banned.snapshot()
	check(banned_snapshot.banned == [["lightning"], ["shield"]] and Network.is_valid_snapshot(banned_snapshot), "bans travel in the snapshot and pass the online schema")
	banned_snapshot.banned = [["lightning", "fireball", "frost"], []]
	check(not Network.is_valid_snapshot(banned_snapshot), "the schema refuses an oversized ban list")
	var replay_a := model_with(["lightning", "fireball", "frost"])
	var replay_b := model_with(["lightning", "fireball", "frost"])
	for copy in [replay_a, replay_b]:
		put(copy, 1, "shield", 900.0)
		copy.place_structure(0, "lightning", 900.0)
		copy.place_structure(0, "fireball", 880.0)
		run_for(copy, 3.0)
	check(replay_a.state_hash() == replay_b.state_hash(), "spells are deterministic")

	# AI targets.
	model = model_with(["lightning", "fireball", "frost"])
	model.configure_deck(1, ["swordsman", "shield", "archer"], ["lightning", "fireball", "frost"])
	put(model, 0, "shield", 500.0)
	check(is_equal_approx(ServerAI.spell_target(model, 1, "lightning"), 500.0), "the AI strikes the strongest enemy")
	check(is_nan(ServerAI.spell_target(model, 1, "fireball")), "the AI keeps its fireball for groups")
	put(model, 0, "swordsman", 520.0); put(model, 0, "archer", 540.0)
	check(not is_nan(ServerAI.spell_target(model, 1, "fireball")), "the AI throws a fireball into a group")
	var ai := ServerAI.new(1, 1)
	check(ai.try_cast_spell(model), "the AI casts a spell from its deck")

	if failures == 0: print("PASS: %d spell checks" % checks)
	quit(1 if failures else 0)
