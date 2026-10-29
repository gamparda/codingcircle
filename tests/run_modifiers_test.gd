extends SceneTree
# Run modifiers (expedition relics, endless-defense boons) change only their own side, and replays keep them.
const RunBoons = preload("res://scripts/run/RunBoons.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func fresh() -> BattleModel:
	var model := BattleModel.new()
	for side in 2:
		model.configure_deck(side, ["shield", "archer", "necromancer", "berserker"], ["wall", "turret", "fireball", "frost"])
	return model

func spawn(model: BattleModel, side: int, kind: String) -> Dictionary:
	model.spawn_cooldowns[side].clear()
	model.resources[side] = 999.0
	check(model.spawn_unit(side, kind), "spawned " + kind)
	return model.units.back()

func _initialize() -> void:
	var plain := fresh()
	var base_shield := spawn(plain, 0, "shield")
	var base_archer := spawn(plain, 0, "archer")

	var model := fresh()
	model.configure_modifiers(0, RunBoons.combine(["steel_plate", "eagle_eye", "barbed_tips", "recruiter", "war_chest"]))
	check(is_equal_approx(model.resources[0], BattleModel.START_RESOURCE + 60.0), "starting funds add to side 0")
	check(is_equal_approx(model.resources[1], BattleModel.START_RESOURCE), "side 1 is untouched")
	var shield := spawn(model, 0, "shield")
	check(is_equal_approx(float(shield.max_hp), float(base_shield.max_hp) * 1.15), "melee health +15%")
	check(is_equal_approx(float(shield.damage), float(base_shield.damage)), "melee damage unchanged")
	var archer := spawn(model, 0, "archer")
	check(is_equal_approx(float(archer.max_hp), float(base_archer.max_hp)), "ranged health unchanged")
	check(is_equal_approx(float(archer.damage), float(base_archer.damage) * 1.15), "ranged damage +15%")
	check(is_equal_approx(float(archer.range), float(base_archer.range) + 40.0), "ranged reach +40")
	check(is_equal_approx(model.unit_cost(0, "archer"), roundf(BattleModel.UNIT_STATS.archer.cost * 0.9)), "units cost 10% less")
	model.resources[0] = 100.0
	model.spawn_cooldowns[0].clear()
	model.spawn_unit(0, "archer")
	check(is_equal_approx(model.resources[0], 100.0 - model.unit_cost(0, "archer")), "spawning charges the reduced cost")
	var enemy := spawn(model, 1, "archer")
	check(is_equal_approx(float(enemy.max_hp), float(base_archer.max_hp)) and is_equal_approx(float(enemy.range), float(base_archer.range)), "enemy units keep their stats")

	# Stars: +20% per level, cost -10% at two stars; tactic stars.
	var starred := fresh()
	starred.configure_modifiers(0, RunBoons.combine([], {"shield": 2, "wall": 1, "fireball": 2}))
	var star_shield := spawn(starred, 0, "shield")
	check(is_equal_approx(float(star_shield.max_hp), float(base_shield.max_hp) * 1.4), "two stars give +40% health")
	check(is_equal_approx(starred.unit_cost(0, "shield"), roundf(BattleModel.UNIT_STATS.shield.cost * 0.9)), "two stars cut the cost")
	starred.resources[0] = 999.0
	check(starred.place_structure(0, "wall", 300.0), "wall placed")
	check(is_equal_approx(float(starred.structures.back().max_hp), float(BattleModel.STRUCTURE_STATS.wall.hp) * 1.2), "a starred wall has +20% health")
	starred.place_structure(0, "fireball", 900.0)
	check(is_equal_approx(float(starred.spell_cooldowns[0].fireball), float(BattleModel.STRUCTURE_STATS.fireball.cooldown) * 0.7), "two-star spells recover 30% faster")

	# Additions and multipliers.
	var mods := RunBoons.combine(["granary", "granary", "grimoire", "masons", "anchor", "bone_urn", "ambush"])
	check(is_equal_approx(float(mods.income), 2.0), "the same boon twice stacks")
	var boosted := fresh()
	boosted.configure_modifiers(0, mods)
	check(is_equal_approx(boosted.resource_income(0), BattleModel.RESOURCE_RATE + 2.0), "income boon")
	boosted.resources[0] = 999.0
	boosted.place_structure(0, "turret", 300.0)
	check(is_equal_approx(float(boosted.structures.back().max_hp), float(BattleModel.STRUCTURE_STATS.turret.hp) * 1.3), "structure health boon")
	boosted.place_structure(0, "frost", 900.0)
	check(is_equal_approx(float(boosted.spell_cooldowns[0].frost), float(BattleModel.STRUCTURE_STATS.frost.cooldown) * 0.8), "spell cooldown boon")
	var striker := spawn(boosted, 0, "berserker")
	var first := boosted._strike_damage(striker)
	var second := boosted._strike_damage(striker)
	check(is_equal_approx(first, second * 2.0), "the first strike deals double damage, once")
	var foe := spawn(boosted, 1, "berserker")
	check(is_equal_approx(boosted._strike_damage(foe), boosted.unit_attack_damage(foe)), "first strike is only for the boon's side")
	var held := spawn(boosted, 0, "shield")
	held.x = 600.0
	boosted._damage_target(foe, held, float(held.max_hp) * 0.6)
	check(is_equal_approx(float(held.x), 600.0 - BattleModel.KNOCKBACK_DISTANCE * 0.5), "heavy boots halve knockback")

	# Validation.
	check(BattleModel.valid_modifiers(mods), "combined boons are valid")
	check(BattleModel.valid_modifiers({"stars": {"shield": 2}}), "stars are valid")
	check(not BattleModel.valid_modifiers({"stars": {"shield": 3}}), "three stars are not")
	check(not BattleModel.valid_modifiers({"stars": {"dragon": 1}}), "unknown card stars are not")
	check(not BattleModel.valid_modifiers({"gold": 5}), "unknown keys are rejected")
	check(not BattleModel.valid_modifiers({"hp:all": -1.0}), "negative multipliers are rejected")
	check(not BattleModel.valid_modifiers({"hp:all": INF}), "infinite values are rejected")
	check(not BattleModel.valid_modifiers([]), "non-dictionaries are rejected")

	# Replays carry modifiers and reproduce the battle.
	var battle := fresh()
	battle.configure_modifiers(0, RunBoons.combine(["war_drum", "aegis", "ambush", "eagle_eye"], {"archer": 1}))
	var recorder := BattleReplay.Recorder.new(battle, 30, {"side": 1, "stage": 4})
	var ai := ServerAI.new(1, 4)
	for tick in 1800:
		if tick % 45 == 0:
			for kind in ["archer", "shield"]:
				if battle.spawn_unit(0, kind):
					recorder.on_spawn(0, kind)
		ai.update(battle, 1.0 / 30.0)
		battle.tick(1.0 / 30.0)
		recorder.on_tick()
		if battle.winner != -1:
			break
	if battle.winner == -1:
		battle.winner = 2
	var replay := recorder.finish(battle)
	check(replay.setup.has("modifiers"), "the replay records the modifiers")
	var json: Variant = JSON.parse_string(JSON.stringify(replay))
	check(BattleReplay.valid(json), "a replay with modifiers is valid after JSON")
	var player := BattleReplay.Player.new(json)
	while player.step():
		pass
	check(player.model.state_hash() == String(replay.result.state_hash), "the replay reproduces the battle with modifiers")
	var plain_replay := BattleReplay.Recorder.new(fresh()).replay
	check(not plain_replay.setup.has("modifiers"), "battles without modifiers keep the old replay shape")
	var tampered: Dictionary = json.duplicate(true)
	tampered.setup.modifiers[0]["hp:all"] = "lots"
	check(not BattleReplay.valid(tampered), "malformed modifiers make the replay invalid")

	# Catalog.
	check(RunBoons.RELICS.size() == 16, "16 relics")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var drawn := RunBoons.draw(rng, 3, ["granary"])
	check(drawn.size() == 3 and not drawn.has("granary") and drawn.all(func(id): return RunBoons.RELICS[id].rarity != "boss"), "draw skips owned and boss relics")
	for id in RunBoons.RELICS:
		check(BattleModel.valid_modifiers(RunBoons.RELICS[id].mods), "relic %s has valid modifiers" % id)
	if failures == 0:
		print("run modifiers test passed")
	quit(1 if failures > 0 else 0)
