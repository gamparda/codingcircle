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
	expect_eq(int(model.resources[0]), 70, "cost is deducted once")
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
	duel.tick(0.01)
	expect_eq(duel.units[1].hp, hp_before, "newly engaged units wait for their first attack tick")
	duel.tick(float(duel.units[0].interval))
	expect_true(duel.units[1].hp < hp_before, "units attack enemies in range")
	var swordsman_stats: Dictionary = BattleModel.UNIT_STATS.swordsman
	var archer_stats: Dictionary = BattleModel.UNIT_STATS.archer
	expect_true(float(swordsman_stats.cost) >= 30.0, "swordsman is not underpriced")
	expect_true(float(swordsman_stats.damage) / float(swordsman_stats.interval) <= 8.0, "swordsman DPS is nerfed below the old value")
	expect_true(float(BattleModel.UNIT_STATS.shield.hp) >= 450.0, "shield has roughly 2.5x the previous health")
	expect_true(
		(float(swordsman_stats.damage) / float(swordsman_stats.interval)) / float(swordsman_stats.cost)
		<= (float(archer_stats.damage) / float(archer_stats.interval)) / float(archer_stats.cost) * 1.6,
		"swordsman cost efficiency stays near other damage units"
	)
	expect_true(float(BattleModel.UNIT_STATS.archer.range) >= 250.0, "archer range is greatly extended")
	expect_true(float(BattleModel.UNIT_STATS.archer.damage) < 20.0, "archer damage is reduced from its old value")
	for kind in BattleModel.UNIT_STATS:
		expect_true(float(BattleModel.UNIT_STATS[kind].interval) >= 1.2, "%s respects the minimum attack/heal interval" % kind)
	expect_true(BattleModel.new().has_method("unit_stat_summary"), "unit stat summary API exists")
	if BattleModel.new().has_method("unit_stat_summary"):
		var stat_summary: String = BattleModel.unit_stat_summary("swordsman")
		expect_true(stat_summary.contains("체력") and stat_summary.contains("공격력") and stat_summary.contains("DPS") and stat_summary.contains("공격 간격") and stat_summary.contains("사거리") and stat_summary.contains("이동"), "unit stat summary exposes all combat stats")
	expect_true(BattleModel.new().has_method("battle_stat_summary"), "battle stat summary API exists")
	if BattleModel.new().has_method("battle_stat_summary"):
		var battle_summary: String = BattleModel.battle_stat_summary()
		expect_true(battle_summary.contains("방벽") and battle_summary.contains("점프대") and battle_summary.contains("늪"), "battle stat summary exposes every structure")
		expect_true(battle_summary.contains("기지 체력") and battle_summary.contains("자원") and battle_summary.contains("제한시간"), "battle stat summary exposes global combat rules")
		expect_true(battle_summary.contains("회복장판"), "battle stat summary exposes the healer pad mechanic")

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
	base_rush.tick(float(base_rush.units[0].interval) + 0.01)
	expect_eq(base_rush.winner, 0, "destroying the enemy base ends the match")

	var healing = BattleModel.new()
	healing.resources[0] = 150.0
	healing.spawn_unit(0, "shield")
	var healer_spawned: bool = healing.spawn_unit(0, "healer")
	expect_true(healer_spawned, "healer can be produced")
	if healer_spawned:
		healing.units[0].x = 400.0
		healing.units[1].x = 400.0
		healing.units[0].hp -= 50.0
		var wounded_hp: float = healing.units[0].hp
		healing.tick(float(healing.units[1].interval) + 0.01)
		expect_true(healing.heal_pads.size() == 1, "healer casting drops a timed heal pad")
		healing.tick(1.0)
		expect_true(healing.units[0].hp > wounded_hp, "heal pad restores a wounded ally standing on it")
		expect_true(healing.units[0].hp <= healing.units[0].max_hp, "healing never exceeds maximum health")
		var pad_model = BattleModel.new()
		pad_model.resources[0] = 150.0
		pad_model.spawn_unit(0, "shield")
		pad_model.spawn_unit(0, "healer")
		pad_model.units[0].x = 400.0
		pad_model.units[0].hp -= 80.0
		pad_model.units[1].x = 400.0
		var pad_wounded: float = pad_model.units[0].hp
		pad_model.tick(float(pad_model.units[1].interval) + 0.01)
		expect_true(pad_model.heal_pads.size() == 1, "healer casting drops a timed heal pad")
		# Heal pad keeps restoring allies standing on it for the full duration.
		pad_model.tick(1.0)
		expect_true(pad_model.units[0].hp > pad_wounded, "heal pad restores wounded allies each tick while active")
		expect_true(pad_model.heal_pads.size() == 1, "heal pad persists through its duration")
		pad_model.tick(4.0)
		expect_true(pad_model.heal_pads.size() == 0, "heal pad expires after its duration")

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

	var NetworkController = load("res://scripts/NetworkController.gd")
	expect_true(NetworkController != null, "NetworkController script loads")
	var network_policy = NetworkController.new()
	var active_model = BattleModel.new()
	expect_true(not network_policy.can_accept_rematch(active_model), "active matches reject rematch requests")
	active_model.winner = 0
	expect_true(network_policy.can_accept_rematch(active_model), "finished matches allow rematch requests")
	network_policy.accepting_players = false
	expect_true(not network_policy.can_accept_rematch(active_model), "server drain rejects rematch requests")

	var accepted_requests := 0
	for index in range(NetworkController.MAX_REQUESTS_PER_SECOND):
		if network_policy.can_process_request(7, 1000):
			accepted_requests += 1
	expect_eq(accepted_requests, NetworkController.MAX_REQUESTS_PER_SECOND, "RPC rate limit accepts the configured burst")
	expect_true(not network_policy.can_process_request(7, 1000), "RPC rate limit rejects excess requests")
	expect_true(network_policy.can_process_request(7, 2001), "RPC rate limit resets after one second")
	expect_true(NetworkController.is_safe_command_text("swordsman"), "known-size command text is accepted")
	expect_true(not NetworkController.is_safe_command_text("x".repeat(33)), "oversized command text is rejected")
	expect_true(not NetworkController.is_safe_command_text("wall&whoami"), "metacharacter command text is rejected")
	expect_true(NetworkController.is_safe_position(640.0), "finite structure position is accepted")
	expect_true(not NetworkController.is_safe_position(NAN), "NaN structure position is rejected")
	expect_true(not NetworkController.is_safe_position(INF), "infinite structure position is rejected")
	var safe_snapshot: Dictionary = BattleModel.new().snapshot()
	expect_true(NetworkController.is_valid_snapshot(safe_snapshot), "authoritative model snapshot is accepted")
	var short_snapshot: Dictionary = safe_snapshot.duplicate(true)
	short_snapshot.resources = [10.0]
	expect_true(not NetworkController.is_valid_snapshot(short_snapshot), "short resource arrays are rejected")
	var unknown_unit_snapshot: Dictionary = safe_snapshot.duplicate(true)
	unknown_unit_snapshot.units = [{"id": 1, "side": 0, "kind": "intruder", "x": 1.0, "hp": 1.0, "max_hp": 1.0, "speed": 1.0}]
	expect_true(not NetworkController.is_valid_snapshot(unknown_unit_snapshot), "unknown unit kinds are rejected")
	var wrong_type_snapshot: Dictionary = safe_snapshot.duplicate(true)
	wrong_type_snapshot.units = [{"id": 1, "side": "zero", "kind": "shield", "x": 1.0, "hp": 1.0, "max_hp": 1.0, "speed": 1.0}]
	expect_true(not NetworkController.is_valid_snapshot(wrong_type_snapshot), "string match sides are rejected instead of coerced")
	var oversized_snapshot: Dictionary = safe_snapshot.duplicate(true)
	oversized_snapshot.units.resize(NetworkController.MAX_SNAPSHOT_UNITS + 1)
	expect_true(not NetworkController.is_valid_snapshot(oversized_snapshot), "oversized unit arrays are rejected")
	var extra_key_snapshot: Dictionary = safe_snapshot.duplicate(true)
	extra_key_snapshot.debug_payload = {"nested": [1, 2, 3]}
	expect_true(not NetworkController.is_valid_snapshot(extra_key_snapshot), "unexpected snapshot keys are rejected")
	var impossible_resource_snapshot: Dictionary = safe_snapshot.duplicate(true)
	impossible_resource_snapshot.resources = [-1.0, 999999.0]
	expect_true(not NetworkController.is_valid_snapshot(impossible_resource_snapshot), "implausible resource values are rejected")
	var populated_model = BattleModel.new()
	expect_true(populated_model.spawn_unit(0, "swordsman"), "snapshot fixture unit spawns")
	var fractional_id_snapshot: Dictionary = populated_model.snapshot()
	fractional_id_snapshot.units[0].id = 1.5
	expect_true(not NetworkController.is_valid_snapshot(fractional_id_snapshot), "non-integral unit IDs are rejected")
	expect_true(NetworkController.is_valid_match_side(0) and NetworkController.is_valid_match_side(1), "valid match sides are accepted")
	expect_true(not NetworkController.is_valid_match_side(-1) and not NetworkController.is_valid_match_side(2), "invalid match sides are rejected")
	var admission_policy = NetworkController.new()
	for peer_id in range(1, NetworkController.MAX_CONNECTIONS_PER_ADDRESS + 1):
		expect_true(admission_policy.register_peer_address(peer_id, "127.0.0.1"), "per-address admission accepts peer %d" % peer_id)
	expect_true(not admission_policy.register_peer_address(99, "127.0.0.1"), "per-address admission rejects excess peers")
	admission_policy.release_peer_address(1)
	expect_true(admission_policy.register_peer_address(99, "127.0.0.1"), "per-address admission recovers after disconnect")
	for strike in range(NetworkController.EARLY_DISCONNECT_LIMIT):
		admission_policy.record_early_disconnect("198.51.100.7", 5000 + strike)
	expect_true(admission_policy.is_address_temporarily_blocked("198.51.100.7", 6000), "repeated early disconnects trigger a temporary block")
	expect_true(not admission_policy.is_address_temporarily_blocked("198.51.100.7", 5000 + NetworkController.ABUSE_BLOCK_MSEC + 100), "temporary connection block expires")
	admission_policy.mark_server_forced_disconnect(200)
	expect_true(not admission_policy.should_penalize_disconnect(200, 1000, 2000), "server-forced orphan disconnect is not penalized")
	expect_true(admission_policy.should_penalize_disconnect(201, 1000, 2000), "voluntary quick disconnect is penalized")
	for match_id in range(NetworkController.MAX_ACTIVE_MATCHES):
		admission_policy.models[match_id] = BattleModel.new()
	expect_true(not admission_policy.can_create_match(), "active match cap prevents model exhaustion")
	admission_policy.free()
	network_policy.free()

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
		expect_true(Main.smoke_connect_allowed(true, "127.0.0.1"), "exported smoke client may connect to loopback")
		expect_true(Main.smoke_connect_allowed(true, "localhost"), "exported smoke client may connect to localhost")
		expect_true(not Main.smoke_connect_allowed(true, "example.com"), "smoke client cannot target external hosts")
		expect_true(not Main.smoke_connect_allowed(false, "127.0.0.1"), "normal clients cannot use smoke connect arguments")

	var BattleView = load("res://scripts/BattleView.gd")
	expect_true(BattleView != null, "BattleView loads with animated unit textures")
	for role in ["tanker", "healer", "archer", "swordsman"]:
		for frame in range(6):
			var texture_path := "res://assets/units/animations/%s/walk_%d.png" % [role, frame]
			var texture = load(texture_path)
			expect_true(texture != null, "%s walk frame %d loads" % [role, frame])
			if texture != null:
				expect_true(texture.get_width() > 0 and texture.get_height() > 0, "%s walk frame %d has dimensions" % [role, frame])

	finish()

func finish() -> void:
	if failures == 0:
		print("PASS: %d checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d checks" % [failures, checks])
		quit(1)
