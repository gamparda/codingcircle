extends SceneTree

var checks := 0
var failures := 0
const Network = preload("res://scripts/NetworkController.gd")
const Save = preload("res://scripts/SaveData.gd")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func model() -> BattleModel:
	var result := BattleModel.new()
	result.configure_deck(0, ["berserker", "warlock", "necromancer"], BattleModel.DEFAULT_STRUCTURE_DECK)
	result.configure_deck(1, ["berserker", "warlock", "necromancer"], BattleModel.DEFAULT_STRUCTURE_DECK)
	result.resources = [180.0, 180.0]
	return result

func _initialize() -> void:
	for entry in [["berserker",155.0,6.0,40.0,40.0], ["warlock",50.0,4.0,280.0,35.0], ["necromancer",50.0,2.0,125.0,110.0]]:
		var battle := model()
		check(battle.spawn_unit(0, entry[0]), "new unit is purchasable: " + entry[0])
		check(battle.units[0].max_hp == entry[1] and battle.units[0].damage == entry[2] and battle.units[0].range == entry[3], "requested stats: " + entry[0])
		check(battle.resources[0] == 180.0 - float(entry[4]), "requested cost: " + entry[0])
	check(Network.validate_deck_payload(["berserker", "warlock", "necromancer"], BattleModel.DEFAULT_STRUCTURE_DECK), "online accepts the new three-unit deck")
	check(not Network.validate_deck_payload(["skeleton", "warlock", "necromancer"], BattleModel.DEFAULT_STRUCTURE_DECK), "summon-only skeleton cannot enter a player deck")
	var data := Save.default_data()
	data.deck_presets[0].units = ["berserker", "warlock", "necromancer"]
	check(Save.sanitize(JSON.parse_string(JSON.stringify(data))).deck_presets[0].units == data.deck_presets[0].units, "new deck survives a saved JSON roundtrip")
	var rage := model()
	rage.spawn_unit(0, "berserker")
	var warrior: Dictionary = rage.units[0]
	warrior.hp = warrior.max_hp * 0.5 + 0.01
	check(not BattleModel.is_enraged(warrior) and is_equal_approx(rage.unit_attack_damage(warrior), 6.0), "above 50 percent retains normal damage")
	warrior.hp = warrior.max_hp * 0.5
	check(BattleModel.is_enraged(warrior), "exactly 50 percent activates rage")
	check(is_equal_approx(rage.unit_attack_damage(warrior), 6.0), "rage retains attack damage of six")
	check(is_equal_approx(rage.support_attack_speed(warrior), 1.5), "rage increases attack speed by 50 percent")
	warrior.support_stacks = 10
	check(is_equal_approx(rage.support_attack_speed(warrior), 1.5 * 1.3), "rage combines with the separate capped mage buff")
	warrior.support_stacks = 0
	warrior.x = 500.0; warrior.speed = 0.0
	rage.configure_deck(1, BattleModel.DEFAULT_UNIT_DECK, BattleModel.DEFAULT_STRUCTURE_DECK)
	rage.spawn_unit(1, "shield")
	var target: Dictionary = rage.units.back()
	target.x = 535.0; target.speed = 0.0; target.cooldown = 999.0
	rage.tick(0.9)
	check(target.hp == 400.0, "rage attack is not prematurely fired")
	rage.tick(0.04)
	check(is_equal_approx(target.hp, 394.0), "actual rage attack lands six damage at the faster cadence")
	warrior.hp = 0.0
	check(not BattleModel.is_enraged(warrior), "dead warrior has no rage state")
	var growth := model()
	growth.configure_campaign_growth(0, 3)
	growth.spawn_unit(0, "berserker")
	growth.units[0].hp = growth.units[0].max_hp * 0.5
	check(is_equal_approx(growth.unit_attack_damage(growth.units[0]), 6.0 * float(BattleModel.campaign_bonuses(3).stat_scale)), "rage damage retains campaign growth")
	var curse := model()
	curse.spawn_unit(0, "warlock")
	curse.spawn_unit(1, "berserker")
	var caster: Dictionary = curse.units[0]
	var victim: Dictionary = curse.units[1]
	caster.x = 500.0; caster.speed = 0.0; caster.cooldown = 0.0
	victim.x = 780.0; victim.speed = 0.0; victim.cooldown = 999.0
	curse.tick(0.01)
	check(is_equal_approx(victim.hp, 151.0), "warlock's actual attack deals four damage")
	check(curse.curses.size() == 1 and curse.curses[0].x == victim.x, "attack installs the curse at the target, not the caster")
	check(is_equal_approx(curse.unit_attack_damage(victim), 6.0 * 0.7), "enemy attack damage is reduced by thirty percent")
	check(is_equal_approx(curse.curse_damage_scale(1, 810.0), 0.7) and curse.curse_damage_scale(1, 810.01) == 1.0, "curse radius is exactly thirty")
	check(curse.curse_damage_scale(0, 780.0) == 1.0, "curse never weakens friendly units")
	curse.spawn_cooldowns[0].clear()
	curse.spawn_unit(0, "warlock")
	var second: Dictionary = curse.units.back()
	second.speed = 0.0; second.cooldown = 999.0
	curse._install_curse(second, 780.0)
	check(curse.curses.size() == 2 and is_equal_approx(curse.unit_attack_damage(victim), 6.0 * 0.7), "overlapping casters do not multiply the reduction")
	curse._install_curse(caster, 900.0)
	check(curse.curses.size() == 2 and curse.curses.any(func(zone): return zone.source_id == caster.id and zone.x == 900.0), "a caster replaces its previous zone")
	check(Network.is_valid_snapshot(curse.snapshot()), "real occupied model snapshot, permanent stacks and curse zones pass online validation")
	var bad := curse.snapshot()
	bad.units[0].support_stacks = 11
	check(not Network.is_valid_snapshot(bad), "reject forged support stacks")
	bad = curse.snapshot(); bad.curses.append(bad.curses[0].duplicate())
	check(not Network.is_valid_snapshot(bad), "reject duplicate curse sources")
	bad = curse.snapshot(); bad.curses[0].x = NAN
	check(not Network.is_valid_snapshot(bad), "reject nonfinite curse positions")
	bad = curse.snapshot(); bad.curses = "wrong type"
	check(not Network.is_valid_snapshot(bad), "reject non-array curse payloads")
	bad = curse.snapshot(); bad.units[0].unexpected = true
	check(not Network.is_valid_snapshot(bad), "schema still rejects unknown fields")
	var legacy := curse.snapshot(); legacy.erase("curses"); legacy.erase("base_max_hp")
	for unit in legacy.units: unit.erase("support_stacks")
	check(Network.is_valid_snapshot(legacy), "legacy six-field snapshots remain accepted")
	caster.hp = 0.0; second.hp = 0.0
	curse.tick(0.01)
	check(curse.curses.size() == 2, "existing five-second zones survive caster death")
	victim.damage = 0.0
	curse.tick(4.99)
	check(curse.curses.is_empty(), "curse expires at five seconds")
	var summon := model()
	summon.spawn_unit(1, "necromancer")
	var necro: Dictionary = summon.units[0]
	necro.x = 1000.0; necro.speed = 0.0
	necro.support_stacks = 10
	summon.tick(4.99)
	check(summon.units.size() == 1, "summon does not occur before five seconds even with an attack-speed buff")
	summon.tick(0.01)
	check(summon.units.size() == 2, "first skeleton appears at exactly five seconds")
	var skull: Dictionary = summon.units.back()
	check(skull.kind == "skeleton" and skull.max_hp == 30.0 and skull.damage == 10.0 and skull.range == 40.0, "skeleton has all requested stats")
	check(skull.side == 1 and skull.x < necro.x, "red-side summons appear ahead in the authoritative direction")
	check(Network.is_valid_snapshot(summon.snapshot()), "skeleton snapshots are accepted online")
	check(not summon.spawn_unit(1, "skeleton"), "skeleton cannot be purchased directly")
	summon.resources[1] = 0.0
	summon.tick(5.0)
	check(summon.units.size() == 3, "subsequent skeleton appears every five seconds")
	check(is_equal_approx(summon.resources[1], BattleModel.RESOURCE_RATE * 5.0), "skeleton summon spends no extra resources")
	necro.hp = 0.0
	summon.tick(5.0)
	check(summon.units.size() == 2 and summon.summon_timers.is_empty(), "dead necromancer stops summoning while existing skeletons remain")
	summon.reset()
	check(summon.units.is_empty() and summon.summon_timers.is_empty() and summon.curses.is_empty(), "new battle clears all trait state")
	var ai_model := model()
	var ai := ServerAI.new(0, 8)
	ai.unit_cursor = 2
	ai._try_spawn(ai_model)
	check(ai_model.units.size() == 1 and ai_model.units[0].kind == "necromancer", "AI can use a selected new-unit deck")
	ai_model.units[0].speed = 0.0
	ai_model.tick(5.0)
	check(ai_model.units.size() == 2 and is_equal_approx(ai_model.units[1].max_hp, 30.0 * float(ai_model.units[0].max_hp) / 50.0) and is_equal_approx(ai_model.units[1].damage, 10.0 * float(ai_model.units[0].damage) / 2.0), "skeleton inherits the summoner's campaign/AI growth")
	if failures == 0:
		print("PASS: %d new-unit mechanics and wire checks" % checks)
	quit(0 if failures == 0 else 1)
