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
	for entry in [["berserker",155.0,8.0,40.0,40.0], ["warlock",50.0,4.0,280.0,35.0], ["necromancer",50.0,2.0,125.0,100.0]]:
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
	check(not BattleModel.is_enraged(warrior) and is_equal_approx(rage.unit_attack_damage(warrior), 8.0), "above 50 percent retains normal damage")
	warrior.hp = warrior.max_hp * 0.5
	check(BattleModel.is_enraged(warrior), "exactly 50 percent activates rage")
	check(is_equal_approx(rage.unit_attack_damage(warrior), 8.0), "rage retains attack damage of eight")
	check(is_equal_approx(rage.support_attack_speed(warrior), 1.5), "rage increases attack speed by 50 percent")
	warrior.support_stacks = 10
	check(is_equal_approx(rage.support_attack_speed(warrior), 1.5 * (1.0 + BattleModel.SUPPORT_INCREMENT * BattleModel.SUPPORT_MAX_STACKS)), "rage combines with the separate capped mage buff")
	warrior.support_stacks = 0
	warrior.x = 500.0; warrior.speed = 0.0
	rage.configure_deck(1, BattleModel.DEFAULT_UNIT_DECK, BattleModel.DEFAULT_STRUCTURE_DECK)
	rage.spawn_unit(1, "shield")
	var target: Dictionary = rage.units.back()
	target.x = 535.0; target.speed = 0.0; target.cooldown = 999.0
	rage.tick(0.9)
	check(target.hp == float(BattleModel.UNIT_STATS.shield.hp), "rage attack is not prematurely fired")
	rage.tick(0.04)
	check(is_equal_approx(target.hp, float(BattleModel.UNIT_STATS.shield.hp) - 8.0), "actual rage attack lands eight damage at the faster cadence")
	warrior.hp = 0.0
	check(not BattleModel.is_enraged(warrior), "dead warrior has no rage state")
	var growth := model()
	growth.configure_campaign_growth(0, 3)
	growth.spawn_unit(0, "berserker")
	growth.units[0].hp = growth.units[0].max_hp * 0.5
	check(is_equal_approx(growth.unit_attack_damage(growth.units[0]), 8.0 * float(BattleModel.campaign_bonuses(3).stat_scale)), "rage damage retains campaign growth")
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
	check(is_equal_approx(curse.unit_attack_damage(victim), 8.0), "curse no longer reduces enemy attack damage")
	check(is_equal_approx(curse.support_attack_speed(victim), BattleModel.CURSE_SPEED_SCALE), "curse slows the enemy attack speed")
	check(is_equal_approx(curse.curse_speed_scale(1, 780.0 + BattleModel.CURSE_RADIUS), BattleModel.CURSE_SPEED_SCALE) and curse.curse_speed_scale(1, 780.01 + BattleModel.CURSE_RADIUS) == 1.0, "curse radius matches CURSE_RADIUS")
	check(curse.curse_speed_scale(0, 780.0) == 1.0, "curse never slows friendly units")
	curse.spawn_cooldowns[0].clear()
	curse.spawn_unit(0, "warlock")
	var second: Dictionary = curse.units.back()
	second.speed = 0.0; second.cooldown = 999.0
	curse._install_curse(second, 780.0)
	check(curse.curses.size() == 2 and is_equal_approx(curse.support_attack_speed(victim), BattleModel.CURSE_SPEED_SCALE), "overlapping casters do not multiply the slow")
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
	var undead := model()
	undead.configure_deck(0, ["zombie", "warlock", "necromancer"], BattleModel.DEFAULT_STRUCTURE_DECK)
	check(undead.spawn_unit(0, "zombie") and BattleModel.has_tag("zombie", "undead") and BattleModel.has_tag("skeleton", "undead") and not BattleModel.has_tag("shield", "undead"), "zombie is purchasable and tagged undead")
	var zombie: Dictionary = undead.units[0]
	zombie.x = 500.0; zombie.speed = 0.0
	var revive_delay := float(BattleModel.trait_value("zombie", "revive_delay"))
	zombie.hp = 0.0
	undead.tick(0.01)
	check(undead.units.size() == 1 and zombie.has("revive_remaining") and undead.drain_combat_events().any(func(event): return event.type == "DOWNED"), "first death downs the zombie instead of removing it")
	check(Network.is_valid_snapshot(undead.snapshot()), "downed zombie snapshots pass online validation")
	undead.configure_deck(1, BattleModel.DEFAULT_UNIT_DECK, BattleModel.DEFAULT_STRUCTURE_DECK)
	undead.spawn_unit(1, "swordsman")
	undead.units.back().x = 520.0; undead.units.back().speed = 0.0
	check(undead._find_target(undead.units.back()) == null, "downed zombie cannot be targeted")
	undead.units.pop_back()
	undead.tick(revive_delay - 0.02)
	check(zombie.has("revive_remaining") and float(zombie.hp) == 0.0, "zombie stays down until the delay ends")
	undead.tick(0.02)
	check(not zombie.has("revive_remaining") and is_equal_approx(float(zombie.hp), float(zombie.max_hp) * float(BattleModel.trait_value("zombie", "revive_hp_fraction"))), "zombie revives once at the data health fraction")
	check(undead.drain_combat_events().any(func(event): return event.type == "REVIVE"), "revive emits an event for the view")
	zombie.hp = 0.0
	undead.tick(0.01)
	check(undead.units.is_empty() and undead.revive_used.is_empty(), "second death is final and clears revive state")
	var forged := model().snapshot()
	forged.units = [{"id": 1, "side": 0, "kind": "swordsman", "x": 300.0, "hp": 0.0, "max_hp": 82.0, "damage": 11.0, "heal": 0.0, "interval": 1.4, "cooldown": 0.0, "speed": 44.0, "range": 40.0, "revive_remaining": 1.0}]
	check(not Network.is_valid_snapshot(forged), "only revivable units may carry a revive timer")
	var holy := model()
	holy.configure_deck(0, ["paladin", "sniper", "zombie"], BattleModel.DEFAULT_STRUCTURE_DECK)
	holy.configure_deck(1, ["zombie", "swordsman", "archer"], BattleModel.DEFAULT_STRUCTURE_DECK)
	check(holy.spawn_unit(0, "paladin"), "paladin is purchasable")
	var paladin: Dictionary = holy.units[0]
	check(is_equal_approx(float(paladin.skill_remaining), float(BattleModel.trait_value("paladin", "skill_cooldown"))), "paladin starts with its skill on cooldown")
	paladin.x = 600.0; paladin.speed = 0.0
	holy.spawn_unit(1, "zombie"); holy.spawn_cooldowns[1].clear(); holy.spawn_unit(1, "swordsman")
	var risen: Dictionary = holy.units[1]
	var blade: Dictionary = holy.units[2]
	risen.x = 640.0; risen.speed = 0.0; risen.cooldown = 999.0
	blade.x = 650.0; blade.speed = 0.0; blade.cooldown = 999.0
	paladin.cooldown = 999.0; paladin.skill_remaining = 0.0
	holy.tick(0.01)
	var skill_damage := float(BattleModel.trait_value("paladin", "skill_damage"))
	var bonus := float(BattleModel.trait_value("paladin", "undead_bonus"))
	check(is_equal_approx(float(blade.hp), float(blade.max_hp) - skill_damage), "skill hits every enemy in the radius")
	check(is_equal_approx(float(risen.hp), float(risen.max_hp) - skill_damage * bonus), "skill deals bonus damage to undead")
	check(is_equal_approx(float(paladin.skill_remaining), float(BattleModel.trait_value("paladin", "skill_cooldown"))), "casting restarts the skill cooldown")
	check(holy.drain_combat_events().any(func(event): return event.type == "SKILL"), "skill emits an event for the view")
	check(Network.is_valid_snapshot(holy.snapshot()), "skill timers pass online validation")
	risen.hp = 1.0; paladin.cooldown = 0.0
	holy.tick(0.01)
	check(not holy.units.has(risen), "an undead slain by the paladin does not revive")
	var forged_skill := holy.snapshot(); forged_skill.units[0].skill_remaining = 999.0
	check(not Network.is_valid_snapshot(forged_skill), "reject skill timers beyond the cooldown")
	var scope := model()
	scope.configure_deck(0, ["paladin", "sniper", "zombie"], BattleModel.DEFAULT_STRUCTURE_DECK)
	scope.configure_deck(1, ["zombie", "swordsman", "archer"], BattleModel.DEFAULT_STRUCTURE_DECK)
	scope.spawn_unit(0, "sniper")
	var sniper: Dictionary = scope.units[0]
	sniper.x = 400.0; sniper.speed = 0.0
	scope.spawn_unit(1, "swordsman"); scope.spawn_cooldowns[1].clear(); scope.spawn_unit(1, "archer")
	var front: Dictionary = scope.units[1]
	var back: Dictionary = scope.units[2]
	front.x = 600.0; back.x = 780.0
	check(scope._find_target(sniper) == back, "sniper picks the in-range enemy farthest behind the line")
	scope.structures.append({"id": 99, "side": 1, "kind": "wall", "x": 500.0, "hp": 230.0, "max_hp": 230.0})
	check(scope._find_target(sniper) == back, "sniper fires over walls")
	back.x = 900.0
	check(scope._find_target(sniper) == front, "sniper ignores enemies beyond its range")
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
	check(skull.kind == "skeleton" and skull.max_hp == 36.0 and skull.damage == 9.0 and skull.range == 40.0, "skeleton has all requested stats")
	check(skull.side == 1 and skull.x < necro.x, "red-side summons appear ahead in the authoritative direction")
	check(Network.is_valid_snapshot(summon.snapshot()), "skeleton snapshots are accepted online")
	check(not summon.spawn_unit(1, "skeleton"), "skeleton cannot be purchased directly")
	summon.resources[1] = 0.0
	summon.tick(5.0)
	check(summon.units.size() == 3, "subsequent skeleton appears every five seconds")
	check(is_equal_approx(summon.resources[1], BattleModel.RESOURCE_RATE * 5.0), "skeleton summon spends no extra resources")
	var capped := model()
	capped.spawn_unit(1, "necromancer")
	capped.units[0].x = 1000.0; capped.units[0].speed = 0.0
	for i in BattleModel.MAX_SKELETONS_PER_NECROMANCER + 2:
		capped.tick(5.0)
		for unit in capped.units: unit.speed = 0.0
	check(capped.units.size() == 1 + BattleModel.MAX_SKELETONS_PER_NECROMANCER, "one necromancer keeps at most the skeleton cap alive")
	check(is_equal_approx(capped.units[0].summon_remaining, BattleModel.SUMMON_INTERVAL), "a full necromancer still restarts its summon timer")
	capped.units[1].hp = 0.0
	capped.tick(0.01)
	check(capped.units.size() == BattleModel.MAX_SKELETONS_PER_NECROMANCER, "a lost skeleton frees a slot without an instant replacement")
	capped.tick(4.99)
	for unit in capped.units: unit.speed = 0.0
	check(capped.units.size() == 1 + BattleModel.MAX_SKELETONS_PER_NECROMANCER, "the freed slot refills on the next summon cycle")
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
	check(ai_model.units.size() == 2 and is_equal_approx(ai_model.units[1].max_hp, 36.0 * float(ai_model.units[0].max_hp) / 50.0) and is_equal_approx(ai_model.units[1].damage, 9.0 * float(ai_model.units[0].damage) / 2.0), "skeleton inherits the summoner's campaign/AI growth")
	if failures == 0:
		print("PASS: %d new-unit mechanics and wire checks" % checks)
	quit(0 if failures == 0 else 1)
