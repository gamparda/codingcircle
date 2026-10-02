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
	check(BattleModel.RESOURCE_RATE == 9.0 and BattleModel.MAX_RESOURCE == 180.0, "base economy improves without campaign bonuses")
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
	ally.x = 540.0; ally.speed = 0.0; ally.hp -= 20.0
	healer.x = 500.0
	opponent.x = 600.0; opponent.speed = 0.0
	var wounded_hp := float(ally.hp)
	var enemy_hp := float(opponent.hp)
	check(support.support_attack_speed(ally) == 1.35, "living mage grants 35 percent attack speed")
	var extra_healer: Dictionary = healer.duplicate(true)
	extra_healer.id = 99
	support.units.append(extra_healer)
	check(support.support_attack_speed(ally) == 1.35, "multiple mages never stack attack speed")
	extra_healer.hp = 0.0
	support.tick(1.61)
	check(float(ally.hp) > wounded_hp and float(opponent.hp) == enemy_hp, "mage prioritizes healing even when an enemy is in range and deals no damage")
	check(support.drain_combat_events().any(func(event): return event.type == "HEAL"), "healing still emits feedback")
	healer.x = 1000.0
	check(support.support_attack_speed(ally) == 1.0, "leaving mage range removes attack speed")
	healer.x = 500.0; healer.hp = 0.0
	check(support.support_attack_speed(ally) == 1.0, "dead mage never grants a buff")
	var save := SaveData.default_data()
	SaveData.record_campaign(save, 1, true, 60.0, 400.0)
	SaveData.record_campaign(save, 1, true, 50.0, 450.0)
	SaveData.record_campaign(save, 2, false, 80.0, 0.0)
	check(SaveData.campaign_growth_level(save) == 1, "replays and defeats never farm extra growth")
	var loaded := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(SaveData.campaign_growth_level(loaded) == 1, "existing save records and JSON roundtrip preserve growth")
	var campaign := BattleModel.new()
	campaign.configure_campaign_growth(0, SaveData.campaign_growth_level(loaded))
	check(campaign.resource_capacity(0) == 190.0 and campaign.resource_income(0) == 9.5 and campaign.resources[0] == 75.0, "first clear increases capacity, income and starting resources")
	campaign.spawn_unit(0, "swordsman")
	check(is_equal_approx(float(campaign.units[0].max_hp), 82.0 * 1.03) and is_equal_approx(float(campaign.units[0].damage), 10.0 * 1.03), "first clear increases unit HP and damage")
	check(campaign.resource_capacity(1) == BattleModel.MAX_RESOURCE and BattleModel.new().resource_capacity(0) == BattleModel.MAX_RESOURCE, "campaign growth never leaks to enemies or online matches")
	SaveData.record_campaign(loaded, 2, true, 65.0, 430.0)
	check(SaveData.campaign_growth_level(loaded) == 2, "each distinct first clear grants one more growth level")
	var view := BattleView.new()
	view.size = Vector2(1280, 500)
	check(is_equal_approx(view.screen_to_world_x(640.0), BattleModel.WORLD_WIDTH / 2.0), "pointer placement uses the extended world's coordinates")
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
