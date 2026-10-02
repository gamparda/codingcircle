extends SceneTree

var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	check(is_equal_approx(BattleModel.FIELD_RIGHT - BattleModel.FIELD_LEFT, 1265.0), "battlefield travel length increases 15 percent")
	check(BattleModel.UNIT_STATS.swordsman.range == 40.0, "swordsman fights behind the tank at range 40")
	check(BattleModel.UNIT_STATS.shield.speed > BattleModel.UNIT_STATS.swordsman.speed and BattleModel.UNIT_STATS.shield.cost == 35.0, "tank arrives before swordsman with lower cost")
	check(BattleModel.UNIT_STATS.shield.damage == 2.0, "tank base damage is nerfed to two")
	check(BattleModel.RESOURCE_RATE == 8.0 and BattleModel.MAX_RESOURCE == 180.0, "base economy improves without campaign bonuses")
	var swamp := BattleModel.new()
	swamp.resources = [180.0, 180.0]
	check(swamp.place_structure(0, "swamp", 500.0), "temporary swamp can be placed")
	swamp.spawn_unit(1, "swordsman")
	var enemy: Dictionary = swamp.units[0]
	enemy.x = 570.0
	check(swamp._swamp_scale(enemy) == 0.2 and BattleModel.STRUCTURE_STATS.swamp.radius == 95.0, "swamp reduces enemy movement 80 percent without increasing radius")
	check(swamp._swamp_scale({"side": 0, "x": 500.0}) == 1.0, "own swamp never slows allies")
	swamp.tick(1.0)
	check(is_equal_approx(570.0 - float(enemy.x), float(enemy.speed) * 0.2), "swamp slowdown actually affects movement")
	swamp.tick(3.99)
	check(swamp.structures.size() == 1, "swamp survives until its five-second deadline")
	swamp.tick(0.01)
	check(swamp.structures.is_empty() and swamp._swamp_scale(enemy) == 1.0, "swamp disappears at five seconds and immediately stops slowing")
	check(swamp._owned_structure_count(0) == 0 and swamp.structure_expirations.is_empty(), "expired swamp frees structure slots and timer state")
	var combat := BattleModel.new()
	combat.resources = [180.0, 180.0]
	combat.configure_deck(0, ["shield", "swordsman", "healer"], ["wall", "swamp", "turret"])
	combat.spawn_unit(0, "shield")
	combat.spawn_unit(0, "swordsman")
	combat.spawn_unit(1, "shield")
	combat.units[0].x = 566.0
	combat.units[1].x = 560.0
	combat.units[2].x = 600.0
	check(combat._find_target(combat.units[2]) == combat.units[0], "enemy melee attacks the front tank rather than rear swordsman")
	var support := BattleModel.new()
	support.resources = [180.0, 180.0]
	support.configure_deck(0, ["shield", "swordsman", "healer"], ["wall", "swamp", "turret"])
	support.spawn_unit(0, "swordsman")
	support.spawn_unit(0, "healer")
	support.spawn_unit(1, "swordsman")
	var ally: Dictionary = support.units[0]
	var healer: Dictionary = support.units[1]
	var opponent: Dictionary = support.units[2]
	ally.x = 625.0; ally.speed = 0.0; ally.hp -= 20.0; ally.damage = 0.0; ally.cooldown = 100.0
	healer.x = 500.0; healer.speed = 0.0
	opponent.x = 510.0; opponent.speed = 0.0; opponent.damage = 0.0; opponent.cooldown = 100.0
	var outside: Dictionary = ally.duplicate(true)
	outside.id = 98; outside.x = 625.01
	support.units.append(outside)
	var wounded_hp := float(ally.hp)
	support.tick(0.01)
	check(support.support_attack_speed(ally) == 1.03, "mage restores range 125 and grants three percent per cast")
	check(support.support_attack_speed(outside) == 1.0 and support.support_attack_speed(opponent) == 1.0, "outside allies and enemies receive no stack")
	check(float(ally.hp) == wounded_hp and float(healer.heal) == 0.0 and float(healer.damage) == 0.0, "mage neither heals nor deals damage")
	check(is_equal_approx(float(healer.cooldown), 7.0), "mage still has seven-second cast cooldown")
	var before := float(ally.cooldown)
	support.tick(0.1)
	check(is_equal_approx(before - float(ally.cooldown), 0.103), "permanent stack changes actual attack cooldown progression")
	check(int(ally.support_stacks) == 1, "mage cannot add stacks while on cooldown")
	healer.x = 1000.0
	support.tick(10.0)
	check(support.support_attack_speed(ally) == 1.03, "stacks do not expire or depend on remaining inside cast radius")
	healer.hp = 0.0
	support.tick(0.01)
	check(support.support_attack_speed(ally) == 1.03, "caster death does not remove stacks from a living recipient")
	support.resources[0] = 180.0
	support.spawn_unit(0, "healer")
	var replacement: Dictionary = support.units.back()
	replacement.x = 500.0; replacement.speed = 0.0
	for _cast in 15:
		replacement.cooldown = 0.0
		support._tick_support(replacement, 0.0)
	check(int(ally.support_stacks) == 10 and is_equal_approx(support.support_attack_speed(ally), 1.30), "multiple casters share the recipient's thirty-percent cap")
	check(not support.drain_combat_events().any(func(event): return event.type == "HEAL"), "support emits no healing events")
	support.spawn_unit(0, "shield")
	check(int(support.units.back().support_stacks) == 0, "new units never inherit another unit's permanent stacks")
	ally.hp = 0.0
	check(support.support_attack_speed(ally) == 1.0, "dead recipients have no active bonus")
	support.reset()
	support.spawn_unit(0, "shield")
	check(int(support.units[0].support_stacks) == 0, "new battles start without permanent stacks")
	var generator := BattleModel.new()
	generator.resources[0] = 100.0
	generator.configure_deck(0, ["shield", "swordsman", "archer"], ["generator", "wall", "swamp"])
	check(generator.place_structure(0, "generator", 280.0), "generator still costs fifty resources")
	generator.tick(1.0)
	check(generator.resources[0] == 60.0 and BattleModel.STRUCTURE_STATS.generator.income == 2.0, "eight base income plus two generator income are applied")
	var save := SaveData.default_data()
	var legacy := SaveData.default_data()
	for _removed_stage in 2:
		legacy.campaign_records.append(SaveData._record())
	legacy.campaign_unlocked = 10
	legacy.stats.highest_campaign = 10
	legacy.campaign_records[0].cleared = true
	legacy.campaign_records[0].best_stars = 3
	legacy.campaign_records[9].cleared = true
	legacy.campaign_records[9].best_stars = 3
	legacy.settings.language = "fr"
	var migrated := SaveData.sanitize(JSON.parse_string(JSON.stringify(legacy)))
	check(migrated.campaign_records.size() == 8 and migrated.campaign_records[0].cleared and migrated.campaign_unlocked == 8, "ten-stage saves preserve surviving records and clamp unlocks to eight")
	check(migrated.stats.highest_campaign == 8 and migrated.stats.total_stars == 3, "retired stages no longer inflate active progress or stars")
	check(migrated.settings.language == "ko", "foreign-language saves migrate to Korean")
	SaveData.record_campaign(save, 1, true, 60.0, 400.0)
	SaveData.record_campaign(save, 1, true, 50.0, 450.0)
	SaveData.record_campaign(save, 2, false, 80.0, 0.0)
	check(SaveData.campaign_growth_level(save) == 1, "replays and defeats never farm extra growth")
	var loaded := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(SaveData.campaign_growth_level(loaded) == 1, "existing save records and JSON roundtrip preserve growth")
	var campaign := BattleModel.new()
	campaign.configure_campaign_growth(0, SaveData.campaign_growth_level(loaded))
	check(campaign.resource_capacity(0) == 190.0 and campaign.resource_income(0) == 8.5 and campaign.resources[0] == 75.0, "first clear increases capacity, income and starting resources")
	campaign.spawn_unit(0, "swordsman")
	check(is_equal_approx(float(campaign.units[0].max_hp), 82.0 * 1.03) and is_equal_approx(float(campaign.units[0].damage), 10.0 * 1.03), "first clear increases unit HP and damage")
	check(campaign.resource_capacity(1) == BattleModel.MAX_RESOURCE and BattleModel.new().resource_capacity(0) == BattleModel.MAX_RESOURCE, "campaign growth never leaks to enemies or online matches")
	SaveData.record_campaign(loaded, 2, true, 65.0, 430.0)
	check(SaveData.campaign_growth_level(loaded) == 2, "each distinct first clear grants one more growth level")
	var view := BattleView.new()
	view.size = Vector2(1280, 500)
	check(is_equal_approx(view.screen_to_world_x(640.0), BattleModel.WORLD_WIDTH / 2.0), "pointer placement uses the extended world's coordinates")
	view.own_side = 1
	check(view.world_to_screen_x(BattleModel.FIELD_RIGHT) < view.world_to_screen_x(BattleModel.FIELD_LEFT), "red player's own fortress is on the left")
	check(view.display_side(1) == 0 and view.display_side(0) == 1, "both players see friendly colors on the left")
	var right_build := BattleModel.RED_REAR_MIN + 20.0
	check(is_equal_approx(view.screen_to_world_x(view.world_to_screen_x(right_build)), right_build), "mirrored construction clicks map back to the real red build zone")
	view.snapshot = {"resources": [180.0, 180.0], "structures": []}
	check(view.placement_error("generator", right_build).is_empty(), "mirrored red player can place a generator in its authoritative rear zone")
	view.free()
	var main_script = load("res://scripts/Main.gd")
	check(main_script != null and main_script.official_connection_candidates(["192.168.0.3"])[0] == main_script.OFFICIAL_SERVER_FALLBACK_ADDRESS, "game server IP precedes both proxy DNS and guessed LAN route")
	var network := NetworkController.new()
	root.add_child(network)
	var messages: Array = []
	network.connection_status.connect(func(text): messages.append(text))
	network.client_connection_state = "connected"
	network._advance_client_connection(NetworkController.ROOM_REQUEST_TIMEOUT + 0.01)
	check(network.client_connection_state == "idle" and not messages.is_empty(), "stalled deck or room response unlocks connection state with an error")
	network.receive_room_created("ABC234")
	network._advance_client_connection(100.0)
	check(network.client_connection_state == "waiting", "created rooms never expire from the request timeout")
	network.client_connection_state = "connecting"
	network.client_connection_candidates = ["127.0.0.2", "127.0.0.1"]
	network.client_connection_index = 0
	network._advance_client_connection(NetworkController.CONNECTION_TIMEOUT + 0.01)
	check(network.client_connection_index == 1, "unreachable addresses advance after the bounded connection timeout")
	network.disconnect_from_server()
	network.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: %d focused balance, growth and connection checks" % checks)
	else:
		printerr("FAILED: %d of %d focused checks" % [failures, checks])
	quit(1 if failures else 0)
